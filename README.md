# FPGA Smart Load Balancer
A fully pipelined Layer-4 load balancer implemented in
synthesizable Verilog, targeting FPGA-based SmartNICs and Data Processing
Units. Designed for AI datacenter workloads where deterministic, line-rate
packet forwarding is non-negotiable.

---

## Key Properties

| Property              | Value                                          |
|-----------------------|------------------------------------------------|
| Target Throughput     | 10 Gbps (64-bit bus @ 156.25 MHz)              |
| Pipeline Latency      | ~12 clock cycles (header -> routing decision)  |
| Initiation Interval   | 1 (one new packet per clock cycle)             |
| Hash Algorithm        | Toeplitz RSS (Microsoft reference key)         |
| Forwarding Table      | 1024-entry BRAM FIB                            |
| Backend Servers       | Up to 8 (configurable)                         |
| Protocol Support      | IPv4/TCP, IPv4/UDP (bypass for ARP/ICMP)       |
| Fmax Target           | > 250 MHz (Xilinx UltraScale+)                 |

---

## Architecture

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
                  │  (RFC 1624 incremental delta)│
                  └─────────────┬────────────────┘
                                │
                          Egress AXIS-M ──> Ethernet MAC
```

---

## Directory Structure

```
├── README.md
├── .gitignore
├── docs/
│   ├── architecture.md         <- Pipeline latency / throughput analysis
│   └── memory_map.md           <- BRAM FIB and token bucket register map
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
│       ├── input_hex_dump.txt  <- Generated by generate_test_traffic.py
│       └── output_hex_dump.txt <- Generated by simulation
├── scripts/
│   ├── networking/
│   │   ├── pcap_to_hex.py
│   │   ├── hex_to_pcap.py
│   │   └── generate_test_traffic.py
│   └── build/
│       ├── run_sim.tcl
│       └── synth_pipeline.tcl
└── synth/constraints/
    ├── timing.sdc
    └── pinout.xdc
```

---

## Quickstart

### 1. Generate Test Traffic

```bash
cd scripts/networking
pip install scapy
python3 generate_test_traffic.py --scenario all --output-dir ../../tb/pcap_data/
```

This generates:
- `tb/pcap_data/input_hex_dump.txt` - 64 mixed TCP/UDP packets
- `tb/pcap_data/elephant_hex_dump.txt` - 200 large elephant-flow packets
- `tb/pcap_data/persistence_hex_dump.txt` - Flow persistence test packets
- A printed table of Python Toeplitz reference hashes for cross-verification

### 2. Run Unit Tests

```bash
# Vivado xsim
vivado -mode batch -source scripts/build/run_sim.tcl

# Or with specific target:
SIM_TARGET=unit_tuple vivado -mode batch -source scripts/build/run_sim.tcl
SIM_TARGET=unit_toeplitz vivado -mode batch -source scripts/build/run_sim.tcl
SIM_TARGET=integration vivado -mode batch -source scripts/build/run_sim.tcl

# ModelSim
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

### 3. Convert Output PCAP and Verify

```bash
cd scripts/networking
# Convert Verilog output hex dump back to PCAP
python3 hex_to_pcap.py \
    -i ../../tb/pcap_data/output_hex_dump.txt \
    -o ../../tb/pcap_data/output_traffic.pcap \
    --verify

# Open in Wireshark to verify DNAT rewrites and checksum correctness:
wireshark tb/pcap_data/output_traffic.pcap
```

### 4. Run Synthesis (Vivado Required)

```bash
vivado -mode batch -source scripts/build/synth_pipeline.tcl
# Reports written to synth/reports/
cat synth/reports/timing_summary.rpt
```

---

## Design Parameters

All top-level parameters are in `rtl/top/l4_load_balancer_top.v`:

| Parameter        | Default | Description                              |
|------------------|---------|------------------------------------------|
| `DATA_WIDTH`     | 64      | AXI-Stream bus width (bits)              |
| `PAYLOAD_FIFO_D` | 1024    | Payload FIFO depth (8-byte words)        |
| `META_FIFO_D`    | 32      | Metadata FIFO depth (entries)            |
| `FIB_INDEX_BITS` | 10      | log2 of FIB table size (1024 entries)    |
| `FIB_INIT_FILE`  | `""`    | Path to $readmemh FIB initialization file|

For **100 Gbps** operation, set `DATA_WIDTH=256` and retarget the clock to
~390 MHz. The Toeplitz core and all downstream logic are parameterized and
will scale automatically.

---

## Verification Matrix

| Scenario                              | Testbench              |
|---------------------------------------|------------------------|
| IPv4/TCP tuple extraction             | tb_tuple_extractor     |
| IPv4/UDP tuple extraction             | tb_tuple_extractor     |
| ARP bypass passthrough                | tb_tuple_extractor     |
| Toeplitz hash determinism             | tb_toeplitz_core       |
| Hash pipeline II=1 back-to-back       | tb_toeplitz_core       |
| Bypass flag propagation               | tb_toeplitz_core       |
| Full pipeline: mice flows             | tb_l4_pipeline_full    |
| Full pipeline: backpressure           | tb_l4_pipeline_full    |
| DNAT checksum correctness (Wireshark) | hex_to_pcap.py --verify|
| Jumbo + minimum frame interleave      | tb_l4_pipeline_full    |

---

## V2.0 Roadmap

- **AXI4-Lite Control Plane**: Memory-mapped FIB update register bank (see
  `docs/memory_map.md` for the planned register layout).
- **Hardware Token Bucket**: Elephant flow detection is already implemented in
  `token_bucket_limiter.v`; V2.0 adds configurable thresholds via AXI4-Lite.
- **256-bit Bus**: Increase `DATA_WIDTH` to 256 for 100 Gbps QSFP28 operation.
- **ECMP / Weighted Round Robin**: Replace Toeplitz hash index with a weighted
  server selection table for non-uniform backend capacity.

---

## References

- [RFC 1624](https://tools.ietf.org/html/rfc1624) - Incremental Internet Checksum
- [Microsoft RSS Toeplitz Key](https://docs.microsoft.com/en-us/windows-hardware/drivers/network/rss-hashing-functions) - Reference key and test vectors
- [Xilinx UG473](https://www.xilinx.com/support/documentation/user_guides/ug473_7Series_Memory_Resources.pdf) - 7-Series BRAM User Guide
- [Xilinx PG203](https://www.xilinx.com/support/documentation/ip_documentation/cmac_usplus/v3_1/pg203-cmac-usplus.pdf) - UltraScale+ CMAC Hard IP

---

*Author: Varrahan Uthayan*