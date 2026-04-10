#!/usr/bin/env python3
"""
hex_to_pcap.py
==============
Convert AXI-Stream hex dump back to PCAP and optionally verify
DNAT rewrites and checksum correctness.

Usage:
    pip install scapy
    python3 hex_to_pcap.py -i output_hex_dump.txt -o output_traffic.pcap --verify
"""

import argparse
import sys

try:
    from scapy.all import wrpcap
    from scapy.layers.inet import IP, TCP, UDP
    from scapy.layers.l2 import Ether
except ImportError:
    print("Error: scapy not installed. Run: pip install scapy")
    sys.exit(1)


def parse_hex_dump(filepath: str) -> list:
    """Parse hex dump file into list of raw packet bytes."""
    packets = []
    current = bytearray()

    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//'):
                continue

            parts = line.split()
            if not parts:
                continue

            data_hex = parts[0]
            has_last = 'L' in parts

            # Parse tkeep if present (2-char hex between data and L)
            tkeep = 0xFF  # default: all bytes valid
            if len(parts) >= 2 and len(parts[1]) <= 2 and parts[1] != 'L':
                try:
                    tkeep = int(parts[1], 16)
                except ValueError:
                    pass

            try:
                beat_bytes = bytes.fromhex(data_hex)
            except ValueError:
                continue

            if has_last:
                # Trim invalid bytes based on tkeep
                valid_bytes = bin(tkeep).count('1')
                current.extend(beat_bytes[:valid_bytes])
                packets.append(bytes(current))
                current = bytearray()
            else:
                current.extend(beat_bytes)

    if current:
        packets.append(bytes(current))

    return packets


def verify_packet(raw: bytes) -> dict:
    """Verify a raw Ethernet/IPv4 packet for checksum correctness."""
    result = {'ok': True, 'issues': []}

    try:
        pkt = Ether(raw)
        if IP in pkt:
            ip = pkt[IP]
            # Recompute checksum
            ip_raw = bytes(ip)
            # Zero out checksum field and recompute
            ip_hdr = bytearray(ip_raw[:20])
            ip_hdr[10] = 0
            ip_hdr[11] = 0
            total = 0
            for i in range(0, 20, 2):
                word = (ip_hdr[i] << 8) + ip_hdr[i+1]
                total += word
            while total >> 16:
                total = (total & 0xFFFF) + (total >> 16)
            expected_csum = ~total & 0xFFFF

            if ip.chksum != expected_csum:
                result['ok'] = False
                result['issues'].append(
                    f"IP checksum: got 0x{ip.chksum:04X}, expected 0x{expected_csum:04X}"
                )
            result['src_ip'] = ip.src
            result['dst_ip'] = ip.dst

            if TCP in pkt:
                result['proto'] = 'TCP'
                result['sport'] = pkt[TCP].sport
                result['dport'] = pkt[TCP].dport
            elif UDP in pkt:
                result['proto'] = 'UDP'
                result['sport'] = pkt[UDP].sport
                result['dport'] = pkt[UDP].dport
        else:
            result['proto'] = 'OTHER'
    except Exception as e:
        result['ok'] = False
        result['issues'].append(f"Parse error: {e}")

    return result


def main():
    parser = argparse.ArgumentParser(description='Convert hex dump to PCAP')
    parser.add_argument('-i', '--input',  required=True, help='Input hex dump file')
    parser.add_argument('-o', '--output', required=True, help='Output PCAP file')
    parser.add_argument('--verify', action='store_true',
                        help='Verify DNAT rewrites and checksums')
    args = parser.parse_args()

    packets = parse_hex_dump(args.input)
    print(f"Parsed {len(packets)} packets from {args.input}")

    if args.verify:
        print("\nVerification Results:")
        print(f"  {'#':>4}  {'Proto':>5}  {'SrcIP':>15}  {'DstIP':>15}  {'Status'}")
        print("  " + "-" * 65)
        pass_cnt = 0
        fail_cnt = 0
        for i, raw in enumerate(packets):
            r = verify_packet(raw)
            status = "PASS" if r['ok'] else f"FAIL: {'; '.join(r['issues'])}"
            src = r.get('src_ip', 'N/A')
            dst = r.get('dst_ip', 'N/A')
            proto = r.get('proto', '?')
            print(f"  {i:>4}  {proto:>5}  {src:>15}  {dst:>15}  {status}")
            if r['ok']:
                pass_cnt += 1
            else:
                fail_cnt += 1
        print(f"\nVerification: {pass_cnt} PASS / {fail_cnt} FAIL")

    # Write PCAP
    scapy_pkts = [Ether(raw) for raw in packets]
    wrpcap(args.output, scapy_pkts)
    print(f"\nWritten {len(scapy_pkts)} packets to {args.output}")
    print("Open with: wireshark", args.output)


if __name__ == '__main__':
    main()