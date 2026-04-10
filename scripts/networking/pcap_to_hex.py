#!/usr/bin/env python3
"""
pcap_to_hex.py
==============
Convert a PCAP file to AXI-Stream hex dump format for use with Verilog testbenches.

Usage:
    pip install scapy
    python3 pcap_to_hex.py -i input.pcap -o output_hex_dump.txt
"""

import argparse
import sys

try:
    from scapy.all import rdpcap, Raw
    from scapy.layers.l2 import Ether
except ImportError:
    print("Error: scapy not installed. Run: pip install scapy")
    sys.exit(1)


def frame_to_hex_beats(frame_bytes: bytes, bus_width: int = 8) -> list:
    """Convert raw frame bytes to bus_width-byte AXI-Stream beats."""
    # Pad to bus_width boundary
    rem = len(frame_bytes) % bus_width
    if rem:
        keep_bytes = bus_width - rem
        frame_bytes = frame_bytes + b'\x00' * keep_bytes
    else:
        keep_bytes = bus_width

    beats = []
    for i in range(0, len(frame_bytes), bus_width):
        chunk = frame_bytes[i:i+bus_width]
        is_last = (i + bus_width >= len(frame_bytes))
        # tkeep: all ones except possibly last beat
        if is_last:
            tkeep = (1 << keep_bytes) - 1
        else:
            tkeep = (1 << bus_width) - 1
        beats.append({
            'data': chunk.hex().upper(),
            'last': is_last,
            'keep': f'{tkeep:02X}',
        })
    return beats


def main():
    parser = argparse.ArgumentParser(description='Convert PCAP to AXI-Stream hex dump')
    parser.add_argument('-i', '--input',  required=True, help='Input PCAP file')
    parser.add_argument('-o', '--output', required=True, help='Output hex dump file')
    parser.add_argument('--bus-width', type=int, default=8,
                        help='AXI-Stream bus width in bytes (default: 8 for 64-bit)')
    parser.add_argument('--max-packets', type=int, default=10000)
    args = parser.parse_args()

    packets = rdpcap(args.input)[:args.max_packets]
    print(f"Read {len(packets)} packets from {args.input}")

    with open(args.output, 'w') as f:
        f.write("// AXI-Stream hex dump from PCAP\n")
        f.write(f"// Bus width: {args.bus_width * 8} bits ({args.bus_width} bytes/beat)\n")
        f.write(f"// Source: {args.input}\n")
        f.write(f"// Packets: {len(packets)}\n")
        f.write("// Format: <data_hex> <tkeep_hex> [L]\n\n")

        for idx, pkt in enumerate(packets):
            raw = bytes(pkt)
            beats = frame_to_hex_beats(raw, args.bus_width)
            f.write(f"// Packet {idx}: {len(raw)} bytes\n")
            for beat in beats:
                f.write(f"{beat['data']} {beat['keep']} {'L' if beat['last'] else ' '}\n")
            f.write('\n')

    print(f"Written to {args.output}")


if __name__ == '__main__':
    main()