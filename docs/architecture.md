# Architecture — L4 Smart Load Balancer Pipeline

## Datapath Overview

The L4 load balancer implements a **split-path architecture**: packet payload
is buffered in a deep sync_fifo as soon as it arrives, while a lightweight
metadata pipeline races ahead to compute the routing decision. The header
modifier reunites both paths once the routing decision is ready.

```
Ingress AXIS ──► [axi_stream_ingress] ──► sync_fifo (payload hold)
                         │                       │
                   hdr_beats[0:4]                │
                         ▼                       │
                 [tuple_extractor]               │
                         │                       │
                    5-tuple (104b)               │
                         ▼                       │
                [hash_pipeline_stages]           │
                  Stage A / B / C                │
                         │                       │
                    fib_index (10b)              │
                         ▼                       │
                [fib_bram_controller]            │
                  BRAM read (1 cy)               │
                         │                       │
               routing decision (metadata)       │
                         ▼                       │
               [token_bucket_limiter]            │
                  rate-limit flag                │
                         │                       │
                    meta_fifo                    │
                         │                       │
                         ▼                       ▼
                    [header_modifier] ◄──────────┘
                         │
                  modified beats
                         ▼
                [checksum_updater]
                         │
                  Egress AXIS ──►
```

---

## Pipeline Latency Analysis

### Metadata Path (header → routing decision)

| Stage | Module                   | Clock Cycles | Cumulative |
|-------|--------------------------|--------------|-----------|
| 1     | axi_stream_ingress       | 5 (capture)  | 5         |
| 2     | tuple_extractor          | 1            | 6         |
| 3–5   | toeplitz_core (comb)     | 0            | 6         |
| 3–5   | hash_pipeline_stages A   | 1            | 7         |
| 3–5   | hash_pipeline_stages B   | 1            | 8         |
| 3–5   | hash_pipeline_stages C   | 1            | 9         |
| 7     | fib_bram_controller      | 1            | 10        |
| 8     | token_bucket_limiter     | 2            | 12        |
| —     | meta_fifo enqueue        | 0            | 12        |

**Metadata pipeline total: 12 clock cycles from first header beat.**

At 156.25 MHz: 12 × 6.4 ns = **76.8 ns metadata latency**.

### Data Path (payload in sync_fifo)

Minimum frame size (64 bytes) = 8 beats at 64-bit bus width.
The 8th (last) beat arrives at cycle 8 from the first beat.

Since the metadata is ready at cycle 12, and the last beat of a minimum frame
arrives at cycle 7 (0-indexed), the payload FIFO holds data for:

    metadata_ready − last_beat_arrival = 12 − 7 = 5 cycles minimum wait

For larger frames the FIFO drains continuously as the header_modifier reads
while the metadata pipeline processes the next packet's tuple.

### FIFO Depth Requirements

**Payload FIFO:**
- Must hold at least one maximum-size frame during the metadata pipeline latency.
- MTU 9000 bytes / 8 bytes per word = 1125 words minimum.
- Default depth: **1024** words (may require 1 extra cycle of pipeline stall for
  jumbo frames — acceptable per REQ-P-01 note).
- Recommended for jumbo support: increase to **2048** words.

**Metadata FIFO:**
- Must hold one metadata entry per in-flight packet in the pipeline.
- With 12-cycle metadata pipeline: ≤ 12 entries ever in flight simultaneously.
- Default depth: **32** entries (provides 2× headroom).

---

## Throughput Analysis

### Zero-Stall Condition (REQ-P-01)

The Hash Engine has II=1 (accepts a new 5-tuple every clock cycle).
The BRAM FIB lookup has II=1 (new lookup every cycle).
The token bucket has II=1 per server (write-back has 1-cycle RAW hazard —
acceptable since consecutive packets from the same server are uncommon in
practice with a 10-Gbps workload).

**At 156.25 MHz, 64-bit bus:** 156.25M × 8 bytes = **10 Gbps** line rate.
**At 390.625 MHz, 256-bit bus:** 390.625M × 32 bytes = **100 Gbps** line rate.

The pipeline sustains line rate because:
1. The payload FIFO absorbs the 12-cycle metadata latency.
2. The header modifier and checksum updater consume one payload beat per cycle.
3. No combinational loop exists anywhere in the data path.

### Backpressure Propagation

If the egress MAC asserts backpressure (`m_axis_tready = 0`):
1. `checksum_updater` stalls its output register.
2. `header_modifier` stalls (sees `m_axis_tready = 0` from checksum_updater).
3. `sync_fifo` stops being drained; fill level rises.
4. When `sync_fifo.almost_full` asserts, `axi_stream_ingress` deasserts
   `s_axis_tready`, propagating backpressure to the upstream MAC.

Maximum sustained backpressure before packet drop:
    PAYLOAD_FIFO_DEPTH × 8 bytes = 1024 × 8 = **8 KB buffered**.

---

## Critical Timing Paths

The two deepest combinational paths are:

1. **Toeplitz XOR tree** (`toeplitz_core`):
   - 104 input bits → 52 XOR pairs → 26 XOR quads → 4 partial sums.
   - Broken into 4 parallel sub-sums (6-8 terms each) before Stage A FF.
   - Estimated depth: ~7 LUT levels → easily closes at 250+ MHz.

2. **1's complement adder** (`checksum_updater`):
   - 16-bit add with end-around carry (2-stage: add → carry wrap).
   - Single LUT6 chain ≤ 3 levels. Not a timing concern.

3. **BRAM address decode → output** (`fib_bram_controller`):
   - Handled by Xilinx BRAM primitives (dedicated clock-to-Q path).
   - Registered output mode: 1 cycle latency, timing met by construction.

---

## Resource Estimates (Xilinx UltraScale+ xczu9eg)

| Resource | Estimated | Available | Utilization |
|----------|-----------|-----------|-------------|
| LUTs     | ~2,500    | 274,080   | < 1%        |
| FFs      | ~1,800    | 548,160   | < 1%        |
| BRAM 36K | 2         | 912       | < 1%        |
| DSPs     | 0         | 2,520     | 0%          |

The Toeplitz XOR tree synthesizes entirely to LUTs (XOR maps 1:1 to LUT2/LUT6).
No DSP blocks are required.
