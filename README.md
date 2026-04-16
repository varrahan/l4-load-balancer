# FPGA Smart Load Balancer

A fully pipelined Layer-4 load balancer implemented in synthesizable Verilog, targeting FPGA-based SmartNICs and Data Processing Units. Built for AI datacenter and high-frequency TCP workloads where deterministic, line-rate packet forwarding is non-negotiable.

Tested and verified on **Xilinx Zynq 7000** and **UltraScale+** device families.

---

## Why This Exists

Software load balancers burn CPU cycles and add microseconds of jitter. In latency-sensitive environments — GPU cluster interconnects, RoCEv2 storage fabrics, high-frequency trading — that overhead is unacceptable. This design pushes the entire L4 forwarding decision into a fixed-latency FPGA pipeline: one packet in, one packet out, every clock cycle, with zero kernel involvement.

---

## Key Properties

| Property | Value |
| --- | --- |
| Pipeline Depth | 9 stages (header parse → routing decision → rewritten egress) |
| Target Throughput | 10 Gbps (64-bit datapath @ 156.25 MHz) |
| Initiation Interval | 1 (one new packet accepted per clock cycle) |
| Hash Algorithm | Toeplitz RSS (Microsoft reference key, deterministic server selection) |
| Forwarding Table | 1024-entry BRAM FIB with `$readmemh` initialization |
| Backend Pool | Up to 8 servers (configurable) |
| Protocol Support | IPv4/TCP, IPv4/UDP (ARP/ICMP bypass passthrough) |
| Header Rewrite | DNAT — destination MAC and IP rewritten per FIB lookup |
| Checksum | RFC 1624 incremental update (no full recomputation) |
| Fmax Target | > 250 MHz on Xilinx UltraScale+ |

---

## Architecture

The design is a single-pass forwarding pipeline. Ingress AXI-Stream frames enter, are parsed for the 5-tuple, hashed via Toeplitz RSS, looked up in a BRAM forwarding table, DNAT-rewritten, and emitted on the egress port — all within a fixed number of clock cycles. A payload sync FIFO decouples the data path from the metadata pipeline, and a token bucket limiter gates forwarding for rate-limited backends.

```
                                    ┌─────────────────────────────────────────────┐
                                    │              PIPELINE STAGES                │
                                    │                                             │
  Ingress         ┌──────────┐      │  ┌──────────┐   ┌──────────┐   ┌─────────┐  │
  AXIS-S ────────>│  AXI-S   │─────>│  │  Tuple   │──>│ Toeplitz │──>│  Hash   │  │
  (Ethernet)      │  Ingress │      │  │ Extractor│   │   Core   │   │  Stage  │  │
                  └────┬─────┘      │  └──────────┘   └──────────┘   └────┬────┘  │
                       │beats       │                                     │       │
                  ┌────▼─────┐      │  ┌──────────┐   ┌──────────┐        │       │
                  │  Payload │      │  │   FIB    │<──│ fib_index│<───────┘       │
                  │  sync_   │      │  │  BRAM    │   └──────────┘                │
                  │  fifo    │      │  └────┬─────┘                               │
                  └────┬─────┘      │       │metadata                             │
                       │            │  ┌────▼─────┐                               │
                       │            │  │  Token   │                               │
                       │            │  │  Bucket  │                               │
                       │            │  └────┬─────┘                               │
                       │            │       │                                     │
                       │            │  ┌────▼─────┐                               │
                       │            │  │  meta_   │                               │
                       │            │  │  fifo    │                               │
                       │            └──└────┬─────┘───────────────────────────────┘
                       │                    │
                  ┌────▼────────────────────▼────┐
                  │        Header Modifier       │
                  │  (DNAT: rewrite DST MAC/IP)  │
                  └─────────────┬────────────────┘
                                │
                  ┌─────────────▼────────────────┐
                  │       Checksum Updater       │
                  │ (RFC 1624 incremental delta) │
                  └─────────────┬────────────────┘
                                │
                          Egress AXIS-M ──> Ethernet MAC
```

**Stage-by-stage summary:**

1. **AXI-Stream Ingress** — Accepts 64-bit AXI-Stream beats, detects SoF/EoF, buffers raw payload into `sync_fifo`.
2. **Tuple Extractor** — Parses Ethernet + IPv4 headers, extracts {src_ip, dst_ip, src_port, dst_port, protocol}. Non-IP traffic (ARP, ICMP) raises a bypass flag.
3. **Toeplitz Core** — Computes a Toeplitz RSS hash over the extracted 5-tuple using the Microsoft reference 40-byte key.
4. **Hash Stage** — Reduces the 32-bit hash output to a FIB index (configurable width, default 10-bit → 1024 entries).
5. **FIB BRAM Lookup** — Single-cycle read from a dual-port BRAM storing `{dst_mac, dst_ip, valid}` per entry.
6. **Token Bucket Limiter** — Per-backend rate gate; drops or marks packets exceeding configured thresholds.
7. **Meta FIFO** — Synchronizes forwarding metadata with the payload data path.
8. **Header Modifier** — Rewrites destination MAC and IP fields in the Ethernet/IPv4 headers (DNAT).
9. **Checksum Updater** — Applies RFC 1624 incremental checksum correction (no full recalculation).

---

## Directory Structure

```
├── README.md
├── .gitignore
├── rtl/
│   ├── top/
│   │   └── l4_load_balancer_top.v
│   ├── parser/
│   │   ├── axi_stream_ingress.v
│   │   └── tuple_extractor.v
│   ├── hash_engine/
│   │   ├── toeplitz_core.v
│   │   └── hash_pipeline_stages.v
│   ├── forwarding/
│   │   ├── fib_bram_controller.v
│   │   └── token_bucket_limiter.v
│   ├── rewrite/
│   │   ├── header_modifier.v
│   │   └── checksum_updater.v
│   └── common/
│       ├── sync_fifo.v
│       └── meta_fifo.v
├── tb/
│   ├── unit/
│   │   ├── tb_tuple_extractor.v
│   │   └── tb_toeplitz_core.v
│   ├── integration/
│   │   └── tb_l4_pipeline_full.v
│   └── pcap_data/
│       ├── input_hex_dump.txt
│       └── output_hex_dump.txt
└── scripts/
    └── networking/
        ├── pcap_to_hex.py
        ├── hex_to_pcap.py
        └── generate_test_traffic.py
```

---

## Quickstart

### 1. Generate Test Traffic

```bash
cd scripts/networking
pip install scapy
python3 generate_test_traffic.py --scenario all --output-dir ../../tb/pcap_data/
```

This produces:

- `input_hex_dump.txt` — 64 mixed TCP/UDP packets
- `elephant_hex_dump.txt` — 200 large elephant-flow packets for token bucket stress testing
- `persistence_hex_dump.txt` — Flow persistence verification packets
- A printed table of Python-computed Toeplitz reference hashes for cross-verification against the RTL

### 2. Run Simulation

```bash
# Vivado xsim (batch mode)
vivado -mode batch -source scripts/build/run_sim.tcl

# Target a specific test suite:
SIM_TARGET=unit_tuple    vivado -mode batch -source scripts/build/run_sim.tcl
SIM_TARGET=unit_toeplitz vivado -mode batch -source scripts/build/run_sim.tcl
SIM_TARGET=integration   vivado -mode batch -source scripts/build/run_sim.tcl

# ModelSim alternative:
SIM=modelsim vsim -do scripts/build/run_sim.tcl
```

Expected unit test output:

```
--- Test 1: IPv4/TCP Packet ---
PASS [TCP_TEST]: SRC=0a000001 DST=c0a80164 SPORT=12345 DPORT=80 PROTO=6

--- Test 2: IPv4/UDP Packet ---
PASS [UDP_TEST]: SRC=ac100503 DST=0a0a0a0a SPORT=53 DPORT=53 PROTO=17

--- Test 3: ARP Bypass ---
PASS [ARP_BYPASS]: tuple_valid correctly not asserted

TEST SUMMARY: 3 PASS / 0 FAIL
```

### 3. Verify Output with Wireshark

```bash
cd scripts/networking
python3 hex_to_pcap.py \
    -i ../../tb/pcap_data/output_hex_dump.txt \
    -o ../../tb/pcap_data/output_traffic.pcap \
    --verify

wireshark tb/pcap_data/output_traffic.pcap
```

Confirm DNAT rewrites and that IPv4 header checksums pass Wireshark validation.

### 4. Synthesize (Vivado)

```bash
vivado -mode batch -source scripts/build/synth_pipeline.tcl
cat synth/reports/timing_summary.rpt
```

---

## Design Parameters

All top-level parameters live in `rtl/top/l4_load_balancer_top.v`:

| Parameter | Default | Description |
| --- | --- | --- |
| `DATA_WIDTH` | 64 | AXI-Stream bus width in bits |
| `PAYLOAD_FIFO_D` | 1024 | Payload FIFO depth (8-byte words) |
| `META_FIFO_D` | 32 | Metadata FIFO depth (entries) |
| `FIB_INDEX_BITS` | 10 | log₂ of FIB table size (default: 1024 entries) |
| `FIB_INIT_FILE` | `""` | Path to `$readmemh` FIB initialization file |

To scale to **100 Gbps**, set `DATA_WIDTH=256` and retarget the clock constraint to ~390 MHz. The Toeplitz core and all downstream stages are fully parameterized and scale without RTL changes.

---

## Verification Matrix

| Scenario | Testbench | Status |
| --- | --- | --- |
| IPv4/TCP tuple extraction | `tb_tuple_extractor` | ✅ |
| IPv4/UDP tuple extraction | `tb_tuple_extractor` | ✅ |
| ARP bypass passthrough | `tb_tuple_extractor` | ✅ |
| Toeplitz hash determinism | `tb_toeplitz_core` | ✅ |
| Hash pipeline II=1 back-to-back throughput | `tb_toeplitz_core` | ✅ |
| Bypass flag propagation through pipeline | `tb_toeplitz_core` | ✅ |
| Full pipeline: mice flow forwarding | `tb_l4_pipeline_full` | ✅ |
| Full pipeline: backpressure handling | `tb_l4_pipeline_full` | ✅ |
| DNAT checksum correctness | `hex_to_pcap.py --verify` | ✅ |
| Jumbo + minimum frame interleave | `tb_l4_pipeline_full` | ✅ |

---

## V2.0 Roadmap

- **AXI4-Lite Control Plane** — Memory-mapped register bank for runtime FIB updates without re-synthesis.
- **Configurable Token Bucket Thresholds** — Elephant flow detection is already implemented in `token_bucket_limiter.v`; V2.0 exposes thresholds via AXI4-Lite.
- **256-bit Datapath** — Increase `DATA_WIDTH` to 256 for 100 Gbps QSFP28 line-rate operation.
- **ECMP / Weighted Round Robin** — Replace the Toeplitz hash-to-index mapping with a weighted server selection table for non-uniform backend capacity.

---

## References

- [RFC 1624](https://tools.ietf.org/html/rfc1624) — Incremental Internet Checksum
- [Microsoft RSS Toeplitz Key](https://docs.microsoft.com/en-us/windows-hardware/drivers/network/rss-hashing-functions) — Reference key and test vectors
- [Xilinx UG473](https://www.xilinx.com/support/documentation/user_guides/ug473_7Series_Memory_Resources.pdf) — 7-Series BRAM User Guide
- [Xilinx PG203](https://www.xilinx.com/support/documentation/ip_documentation/cmac_usplus/v3_1/pg203-cmac-usplus.pdf) — UltraScale+ CMAC Hard IP