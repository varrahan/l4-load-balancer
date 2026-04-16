# Formal Verification

This directory contains SymbiYosys (sby) formal verification setups for the
L4 load balancer RTL. Each subdirectory targets one module and contains a
property file (`.sv`) and a sby configuration file (`.sby`).

---

## Toolchain

| Tool | Role |
|---|---|
| [SymbiYosys](https://github.com/YosysHQ/sby) | Front-end orchestrator |
| [Yosys](https://github.com/YosysHQ/yosys) | RTL elaboration and synthesis |
| [smtbmc](https://github.com/YosysHQ/yosys/tree/master/backends/smt2) | BMC/induction engine |
| [Yices2](https://yices.csl.sri.com/) | SMT solver backend |

### Installation (Ubuntu / Debian)

```bash
# OSS CAD Suite bundles all of the above:
wget https://github.com/YosysHQ/oss-cad-suite-build/releases/latest/download/oss-cad-suite-linux-x64-<date>.tgz
tar xf oss-cad-suite-linux-x64-<date>.tgz
source oss-cad-suite/environment
```

Or via package manager:

```bash
apt install symbiyosys yosys yices2
```

---

## Verification Mode

All targets run **Bounded Model Checking (BMC)**. The bound depth is chosen
per module to be deep enough to exercise the full pipeline latency plus a
margin:

| Module | BMC Depth | Rationale |
|---|---|---|
| `sync_fifo` | 20 | Covers fill → full → drain cycle for DEPTH=4 |
| `meta_fifo` | 20 | Same as sync_fifo |
| `tuple_extractor` | 12 | Covers 5-beat parse window + slack |
| `toeplitz_core` | 16 | Covers 3-stage latency + II=1 back-to-back |
| `fib_bram_controller` | 12 | Covers 2-stage lookup latency + II=1 |
| `token_bucket_limiter` | 32 | Covers refill period (REFILL_PERIOD=4 in props) |
| `header_modifier` | 20 | Covers 8-beat packet window |

---

## Running

### All targets

```bash
cd <repo-root>
bash formal/run_formal.sh
```

### Single target

```bash
sby -f formal/sync_fifo/sync_fifo.sby
sby -f formal/meta_fifo/meta_fifo.sby
sby -f formal/tuple_extractor/tuple_extractor.sby
sby -f formal/toeplitz_core/toeplitz_core.sby
sby -f formal/header_modifier/header_modifier.sby
sby -f formal/fib_bram_controller/fib_bram_controller.sby
sby -f formal/token_bucket_limiter/token_bucket_limiter.sby
```

Each target writes results under `formal/<module>/<module>/` (sby work
directory). Check `engine_0/trace.vcd` on a failure for a counterexample
waveform.

---

## Property Summary

### `sync_fifo`

| Property | Type | Description |
|---|---|---|
| `assert_reset_empty` | assert | `empty` asserted immediately after reset |
| `assert_reset_not_full` | assert | `full` deasserted after reset |
| `assert_reset_not_valid` | assert | `valid` deasserted after reset |
| `assert_no_overflow` | assert | Writing into a full FIFO does not advance `wr_ptr` |
| `assert_no_underflow` | assert | Reading from empty FIFO does not advance `rd_ptr` |
| `assert_occ_bound` | assert | Occupancy (`wr_ptr − rd_ptr`) ≤ DEPTH at all times |
| `assert_full_empty_mutex` | assert | `full` and `empty` are never simultaneously asserted |
| `assert_valid_tracks_rden` | assert | `valid` is never high when previous cycle had no `rd_en` |
| `fill_and_drain` | cover | FIFO transitions from `full` to `empty` |
| `write_then_read` | cover | A single write followed by a read produces `valid` output |

### `meta_fifo`

| Property | Type | Description |
|---|---|---|
| `assert_reset_empty` | assert | Empty after reset |
| `assert_reset_not_valid` | assert | `rd_valid` deasserted after reset |
| `assert_no_overflow` | assert | Full FIFO + write only stays full |
| `assert_no_underflow_valid` | assert | Reading empty FIFO does not assert `rd_valid` |
| `assert_occ_bound` | assert | Occupancy ≤ DEPTH |
| `assert_valid_tracks_rden` | assert | `rd_valid` requires prior `rd_en` |
| `single_roundtrip` | cover | Write then read produces valid output |

### `tuple_extractor`

| Property | Type | Description |
|---|---|---|
| `assert_mutex` | assert | `tuple_valid` and `bypass` never simultaneously high |
| `assert_valid_pulse` | assert | `tuple_valid` is a single-cycle pulse |
| `assert_bypass_pulse` | assert | `bypass` is a single-cycle pulse |
| `assert_reset_valid` | assert | `tuple_valid` deasserted after reset |
| `assert_reset_bypass` | assert | `bypass` deasserted after reset |
| `assert_valid_at_beat4` | assert | `tuple_valid` only fires after beat 4 |
| `assert_bypass_at_beat4` | assert | `bypass` only fires after beat 4 |
| `assert_beat_bound` | assert | `beat_cnt` never exceeds 7 |
| `assert_beat_reset_on_tlast` | assert | `beat_cnt` resets to 0 after `tlast` |
| `tcp_valid_reached` | cover | TCP tuple extraction is reachable |
| `udp_valid_reached` | cover | UDP tuple extraction is reachable |
| `arp_bypass_reached` | cover | ARP bypass is reachable |

### `toeplitz_core`

| Property | Type | Description |
|---|---|---|
| `assert_latency_3` | assert | `out_valid` arrives exactly 3 cycles after `in_valid` |
| `assert_bypass_latency` | assert | `out_bypass` propagates with same 3-cycle latency |
| `assert_reset_valid` | assert | `out_valid` deasserted after reset |
| `assert_reset_bypass` | assert | `out_bypass` deasserted after reset |
| `assert_ii1` | assert | Back-to-back valid inputs produce back-to-back valid outputs |
| `assert_valid_bypass_mutex` | assert | `out_valid` and `out_bypass` never simultaneously asserted |
| `nonzero_hash` | cover | A non-zero hash output is reachable |
| `ii1_cover` | cover | Two consecutive `out_valid` cycles are reachable |

### `header_modifier`

| Property | Type | Description |
|---|---|---|
| `assert_reset_mvalid` | assert | `m_tvalid` deasserted after reset |
| `assert_stall_no_meta` | assert | `s_tready` deasserted when packet start has no meta |
| `assert_bypass_passthrough` | assert | Bypass packets are forwarded byte-for-byte unmodified |
| `assert_beat0_mac` | assert | Beat 0 output bits [63:16] carry the new `dst_mac` |
| `assert_beat0_tail` | assert | Beat 0 bits [15:0] (bytes 6-7) are preserved |
| `assert_beat3_dip_hi` | assert | Beat 3 bits [15:0] carry `new_dst_ip[31:16]` |
| `assert_beat4_dip_lo` | assert | Beat 4 bits [63:48] carry `new_dst_ip[15:0]` |
| `assert_meta_ready_pulse` | assert | `meta_ready` is a single-cycle pulse |
| `assert_beat_bound` | assert | `beat_cnt` never exceeds 7 |
| `bypass_forwarded` | cover | Bypass packet forwarded to egress |
| `dnat_rewrite_full` | cover | Non-bypass packet forwarded after DNAT rewrite |

### `fib_bram_controller`

| Property | Type | Description |
|---|---|---|
| `assert_latency_2` | assert | `out_valid` arrives exactly 2 cycles after `in_valid` |
| `assert_bypass_latency` | assert | `out_bypass` propagates with same 2-cycle latency |
| `assert_reset_valid` | assert | `out_valid` deasserted after reset |
| `assert_reset_bypass` | assert | `out_bypass` deasserted after reset |
| `assert_addr_bound` | assert | BRAM address index always within `[0, FIB_DEPTH)` |
| `assert_ii1` | assert | Back-to-back lookups produce back-to-back valid outputs |
| `assert_server_id_bound` | assert | `server_id` output is within `[0, 7]` |
| `valid_lookup` | cover | Non-bypass lookup completes |
| `bypass_lookup` | cover | Bypass lookup completes |

### `token_bucket_limiter`

| Property | Type | Description |
|---|---|---|
| `assert_token_floor` | assert | Token count never underflows (no negative tokens) |
| `assert_token_ceiling` | assert | Token count never exceeds `BUCKET_SIZE` |
| `assert_bypass_always_permit` | assert | Bypass packets are always permitted |
| `assert_permit_when_enough` | assert | Packet is permitted when tokens ≥ `PKT_COST` |
| `assert_drop_when_empty` | assert | Packet is dropped when tokens < `PKT_COST` |
| `assert_refill_cnt_bound` | assert | `refill_cnt` never exceeds `REFILL_PERIOD − 1` |
| `assert_out_valid_latency` | assert | `out_valid` is `in_valid` delayed by 1 cycle |
| `assert_reset_out_valid` | assert | `out_valid` deasserted after reset |
| `packet_dropped` | cover | A drop event (permit=0) is reachable |
| `packet_permitted` | cover | A permit event (permit=1) is reachable |
| `refill_fires` | cover | A refill tick is reachable |

---

## Known Limitations

**`checksum_updater`** — The V1 implementation explicitly defers the RFC 1624
patch to a future revision (see the `beat 4` comment in the source). A full
formal proof of the checksum invariant requires the two-packet look-ahead
buffer described in the V2 design note. A property stub is included in
`formal/checksum_updater/` to document the intended invariant; it is not
wired into CI until the V2 implementation lands.

**BMC vs. induction** — BMC at a finite depth cannot prove unbounded
properties (e.g. "tokens never overflow for all time"). To promote selected
assertions to full inductive proofs, change `mode bmc` to `mode prove` in the
relevant `.sby` file. This requires stronger invariants on the initial state
and will increase solver runtime significantly.

**FIB size** — `fib_bram_controller_props` uses `FIB_INDEX_BITS=4` (16
entries) to keep BMC tractable. The production parameter is 10 (1024 entries);
the structural properties (latency, bypass, address bound) are independent of
FIB size, so the reduced parameter does not weaken the proofs.

**`token_bucket_limiter` server count** — Props use `NUM_SERVERS=2` to keep
the state space manageable. The invariants (floor, ceiling, bypass permit) are
per-server and hold for any `NUM_SERVERS` by the same argument; increasing
`NUM_SERVERS` in the props file will exercise more servers at the cost of
longer solve times.
