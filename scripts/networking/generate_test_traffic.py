#!/usr/bin/env python3
"""
generate_test_traffic.py
========================
Generates AXI-Stream hex dumps for the FPGA load balancer testbench.

Usage:
    python3 generate_test_traffic.py --scenario all --output-dir ../../tb/pcap_data/

Outputs:
    input_hex_dump.txt      - 64 mixed TCP/UDP packets
    elephant_hex_dump.txt   - 200 large elephant-flow packets
    persistence_hex_dump.txt - Flow persistence test packets

Also prints Python-computed Toeplitz reference hashes for cross-verification.
"""

import argparse
import struct
import random
import os
from typing import List, Tuple

# ---------------------------------------------------------------------------
# Microsoft RSS Toeplitz key (40 bytes)
# ---------------------------------------------------------------------------
RSS_KEY = bytes([
    0x6D, 0x5A, 0x56, 0xDA, 0x25, 0x5B, 0x0E, 0xC2,
    0x41, 0x67, 0x25, 0x3D, 0x43, 0xA3, 0x8F, 0xB0,
    0xD0, 0xCA, 0x2B, 0xCB, 0xAE, 0x7B, 0x30, 0xB4,
    0x77, 0xCB, 0x2D, 0xA3, 0x80, 0x30, 0xF2, 0x0C,
    0x6A, 0x42, 0xB7, 0x3B, 0xBE, 0xAC, 0x01, 0xFA,
])


def toeplitz_hash(src_ip: int, dst_ip: int, src_port: int, dst_port: int) -> int:
    """Compute Microsoft RSS Toeplitz hash for a 4-tuple."""
    # Input: 96 bits = src_ip[31:0] + dst_ip[31:0] + src_port[15:0] + dst_port[15:0]
    input_bytes = (
        src_ip.to_bytes(4, 'big') +
        dst_ip.to_bytes(4, 'big') +
        src_port.to_bytes(2, 'big') +
        dst_port.to_bytes(2, 'big')
    )
    result = 0
    # Extend key for bit-indexed access (need key[0..126])
    key_int = int.from_bytes(RSS_KEY, 'big')
    for byte_idx, byte in enumerate(input_bytes):
        for bit_idx in range(8):
            if byte & (0x80 >> bit_idx):
                pos = byte_idx * 8 + bit_idx
                # key[pos..pos+31] MSB-first from the 320-bit key
                shift = (320 - pos - 32)
                if shift >= 0:
                    key_word = (key_int >> shift) & 0xFFFFFFFF
                else:
                    # Wrap at end of key - extend with zeros per spec
                    key_word = (key_int << (-shift)) & 0xFFFFFFFF
                result ^= key_word
    return result & 0xFFFFFFFF


def make_eth_ipv4_tcp_frame(
    src_mac: bytes,
    dst_mac: bytes,
    src_ip: int,
    dst_ip: int,
    src_port: int,
    dst_port: int,
    payload: bytes = b'\xDE\xAD\xBE\xEF',
    ttl: int = 64,
) -> bytes:
    """Build a minimal Ethernet/IPv4/TCP frame (no options, no actual TCP sequence fields)."""
    # Ethernet header (14 bytes)
    eth = dst_mac + src_mac + b'\x08\x00'

    # IPv4 header (20 bytes, no options)
    ip_len = 20 + 20 + len(payload)  # IP hdr + TCP hdr + payload
    ipv4_no_csum = struct.pack(
        '!BBHHHBBH4s4s',
        0x45,            # version + IHL
        0x00,            # DSCP/ECN
        ip_len,          # Total Length
        random.randint(1, 0xFFFF),  # ID
        0x4000,          # Flags=DF, Frag=0
        ttl,             # TTL
        6,               # Protocol: TCP
        0,               # Checksum placeholder
        src_ip.to_bytes(4, 'big'),
        dst_ip.to_bytes(4, 'big'),
    )
    # Compute IPv4 checksum
    csum = _ipv4_checksum(ipv4_no_csum)
    ipv4 = ipv4_no_csum[:10] + struct.pack('!H', csum) + ipv4_no_csum[12:]

    # Minimal TCP header (20 bytes)
    tcp = struct.pack(
        '!HHIIBBHHH',
        src_port,   # SrcPort
        dst_port,   # DstPort
        0,          # SeqNum
        0,          # AckNum
        0x50,       # Data offset = 5 (20 bytes), reserved = 0
        0x02,       # Flags: SYN
        0xFFFF,     # Window
        0,          # Checksum (0 for simplicity)
        0,          # UrgPtr
    )

    return eth + ipv4 + tcp + payload


def make_eth_ipv4_udp_frame(
    src_mac: bytes,
    dst_mac: bytes,
    src_ip: int,
    dst_ip: int,
    src_port: int,
    dst_port: int,
    payload: bytes = b'\xCA\xFE',
) -> bytes:
    """Build a minimal Ethernet/IPv4/UDP frame."""
    eth = dst_mac + src_mac + b'\x08\x00'

    udp_len = 8 + len(payload)
    ip_len = 20 + udp_len
    ipv4_no_csum = struct.pack(
        '!BBHHHBBH4s4s',
        0x45, 0x00, ip_len,
        random.randint(1, 0xFFFF),
        0x4000, 64, 17, 0,
        src_ip.to_bytes(4, 'big'),
        dst_ip.to_bytes(4, 'big'),
    )
    csum = _ipv4_checksum(ipv4_no_csum)
    ipv4 = ipv4_no_csum[:10] + struct.pack('!H', csum) + ipv4_no_csum[12:]
    udp = struct.pack('!HHHH', src_port, dst_port, udp_len, 0)
    return eth + ipv4 + udp + payload


def make_arp_frame(src_mac: bytes, src_ip: int, dst_ip: int) -> bytes:
    """Build an ARP request frame."""
    dst_mac = b'\xFF\xFF\xFF\xFF\xFF\xFF'
    eth = dst_mac + src_mac + b'\x08\x06'
    arp = struct.pack(
        '!HHBBH6s4s6s4s',
        1,       # Ethernet
        0x0800,  # IPv4
        6, 4,    # HW size, Proto size
        1,       # Request
        src_mac, src_ip.to_bytes(4, 'big'),
        b'\x00' * 6, dst_ip.to_bytes(4, 'big'),
    )
    return eth + arp


def _ipv4_checksum(header: bytes) -> int:
    """One's complement checksum over a 20-byte IPv4 header."""
    total = 0
    for i in range(0, len(header), 2):
        word = (header[i] << 8) + header[i+1]
        total += word
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return ~total & 0xFFFF


def frame_to_hex_beats(frame: bytes) -> List[str]:
    """Convert a frame to 8-byte AXI-Stream beats in hex, with tlast marker."""
    beats = []
    frame = frame.ljust((len(frame) + 7) // 8 * 8, b'\x00')  # pad to 8-byte boundary
    for i in range(0, len(frame), 8):
        chunk = frame[i:i+8]
        is_last = (i + 8 >= len(frame))
        hex_str = chunk.hex().upper()
        beats.append(f"{hex_str} {'L' if is_last else ' '}")
    return beats


def write_hex_dump(frames: List[bytes], filepath: str) -> None:
    """Write all frames to a hex dump file."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w') as f:
        f.write("// AXI-Stream hex dump - 8 bytes/beat, 'L' = tlast\n")
        f.write("// Format: <beat_data_hex> [L]\n")
        f.write(f"// Total packets: {len(frames)}\n\n")
        for pkt_idx, frame in enumerate(frames):
            f.write(f"// Packet {pkt_idx}\n")
            for beat in frame_to_hex_beats(frame):
                f.write(beat + '\n')
            f.write('\n')
    print(f"  Written {len(frames)} packets → {filepath}")


# ---------------------------------------------------------------------------
# Scenario generators
# ---------------------------------------------------------------------------

SRC_MAC  = bytes.fromhex('AABBCCDDEEFF')
DST_MAC  = bytes.fromhex('001122334455')
SERVERS  = [f'10.0.0.{i}' for i in range(1, 9)]

def _ip(s: str) -> int:
    parts = [int(x) for x in s.split('.')]
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]


def generate_mixed(count: int = 64) -> Tuple[List[bytes], List[dict]]:
    """Generate count mixed TCP/UDP packets with random 5-tuples."""
    frames = []
    meta = []
    rng = random.Random(42)
    for i in range(count):
        proto = 'tcp' if rng.random() > 0.4 else 'udp'
        src_ip  = _ip(f'10.{rng.randint(0,255)}.{rng.randint(0,255)}.{rng.randint(1,254)}')
        dst_ip  = _ip(f'192.168.1.{rng.randint(1,254)}')
        sport   = rng.randint(1024, 65535)
        dport   = rng.choice([80, 443, 8080, 8443, 53, 22, 3306])
        payload = bytes([rng.randint(0, 255) for _ in range(rng.randint(0, 32))])

        if proto == 'tcp':
            frame = make_eth_ipv4_tcp_frame(SRC_MAC, DST_MAC, src_ip, dst_ip, sport, dport, payload)
        else:
            frame = make_eth_ipv4_udp_frame(SRC_MAC, DST_MAC, src_ip, dst_ip, sport, dport, payload)

        h = toeplitz_hash(src_ip, dst_ip, sport, dport)
        frames.append(frame)
        meta.append({'proto': proto, 'src_ip': src_ip, 'dst_ip': dst_ip,
                     'sport': sport, 'dport': dport, 'hash': h})
    return frames, meta


def generate_elephant(count: int = 200) -> List[bytes]:
    """Generate large elephant flow packets (≥1KB payload)."""
    frames = []
    rng = random.Random(99)
    # One persistent elephant flow
    src_ip = _ip('10.0.0.1')
    dst_ip = _ip('192.168.1.100')
    sport, dport = 50000, 80
    for _ in range(count):
        payload = bytes([rng.randint(0, 255) for _ in range(1024)])
        frames.append(make_eth_ipv4_tcp_frame(SRC_MAC, DST_MAC, src_ip, dst_ip, sport, dport, payload))
    return frames


def generate_persistence(count: int = 20) -> List[bytes]:
    """Generate flow persistence test: same 5-tuple repeated, verify same server selected."""
    frames = []
    src_ip = _ip('172.16.5.3')
    dst_ip = _ip('192.168.1.1')
    sport, dport = 12345, 80
    for _ in range(count):
        frames.append(make_eth_ipv4_tcp_frame(SRC_MAC, DST_MAC, src_ip, dst_ip, sport, dport))
    return frames


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description='Generate test traffic hex dumps')
    parser.add_argument('--scenario', choices=['mixed', 'elephant', 'persistence', 'all'],
                        default='all')
    parser.add_argument('--output-dir', default='../../tb/pcap_data/')
    args = parser.parse_args()

    out = args.output_dir
    os.makedirs(out, exist_ok=True)

    print("=" * 60)
    print("FPGA Load Balancer - Test Traffic Generator")
    print("=" * 60)

    if args.scenario in ('mixed', 'all'):
        print("\n[mixed] Generating 64 mixed TCP/UDP packets...")
        frames, meta = generate_mixed(64)
        write_hex_dump(frames, os.path.join(out, 'input_hex_dump.txt'))

        # Print Toeplitz reference hashes for top-10 packets
        print("\nToeplitz Reference Hashes (Python - first 10 packets):")
        print(f"  {'#':>3}  {'Proto':>5}  {'SrcIP':>15}  {'SrcPort':>7}  {'Hash':>10}")
        print("  " + "-" * 50)
        for i, m in enumerate(meta[:10]):
            sip = '.'.join(str((m['src_ip'] >> (8*(3-j))) & 0xFF) for j in range(4))
            print(f"  {i:>3}  {m['proto']:>5}  {sip:>15}  {m['sport']:>7}  0x{m['hash']:08X}")

    if args.scenario in ('elephant', 'all'):
        print("\n[elephant] Generating 200 elephant flow packets...")
        frames = generate_elephant(200)
        write_hex_dump(frames, os.path.join(out, 'elephant_hex_dump.txt'))

    if args.scenario in ('persistence', 'all'):
        print("\n[persistence] Generating 20 flow persistence packets...")
        frames = generate_persistence(20)
        write_hex_dump(frames, os.path.join(out, 'persistence_hex_dump.txt'))

        # Verify single hash value
        src_ip = _ip('172.16.5.3')
        dst_ip = _ip('192.168.1.1')
        h = toeplitz_hash(src_ip, dst_ip, 12345, 80)
        print(f"\n  Persistence flow Toeplitz hash: 0x{h:08X}")
        print(f"  Expected FIB index (10 bits): {h & 0x3FF}")
        print(f"  Expected server_id (hash%8): {(h & 0x3FF) % 8}")

    print("\nDone. Use these files with the Verilog testbenches.")
    print("Cross-check the Python hashes against RTL simulation output.")


if __name__ == '__main__':
    main()