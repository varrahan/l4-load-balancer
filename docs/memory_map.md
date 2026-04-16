# Memory Map — L4 Smart Load Balancer

## 1. Forwarding Information Base (FIB) BRAM

### Physical Configuration

| Parameter         | Value                          |
|-------------------|--------------------------------|
| BRAM Type         | True Dual-Port Block RAM       |
| Data Width        | 96 bits per entry              |
| Address Width     | 10 bits (1024 entries)         |
| Total Capacity    | 96 × 1024 = 98,304 bits ≈ 12 KB |
| FPGA Primitive    | RAMB36E2 (2 × RAMB18 equivalent) |
| Read Latency      | 1 clock cycle (registered mode)|
| Write Latency     | 1 clock cycle                  |

### Entry Encoding (96 bits per slot)

```
Bit Range    Field                    Width    Description
-----------  -----------------------  -------  ----------------------------------------
[95:48]      Backend Destination MAC  48 bits  MAC address of backend server NIC
[47:16]      Backend Destination IP   32 bits  IPv4 address of backend server
[15:8]       Server Index             8 bits   Backend index 0-7 (identifies which server)
[7]          Server Health/Enable     1 bit    1 = server is UP and accepting traffic
[6]          Rate-Limit Enable        1 bit    1 = apply token bucket rate limiting
[5:0]        Reserved / Padding       6 bits   Must be written as 0; reads undefined
```

### Address Space

```
FIB Address    Mapped Backend    Condition
[0x000-0x0FF]  Backend pool      hash[31:22] ^ hash[21:12] ^ hash[11:2] ^ hash[1:0]
               (hash folded to   distributes ~uniformly across all 1024 slots
               10-bit index)
[0x000-0x3FF]  All 1024 entries  Active range
```

### Backend Server Assignment

With 8 backend servers, the `server_idx` field cycles through 0–7:

```
FIB Slot     Server Index  Default IP          Default MAC
0x000-0x07F  0             192.168.10.0        DE:AD:BE:00:00:00
0x080-0x0FF  1             192.168.10.1        DE:AD:BE:00:00:01
0x100-0x17F  2             192.168.10.2        DE:AD:BE:00:00:02
0x180-0x1FF  3             192.168.10.3        DE:AD:BE:00:00:03
0x200-0x27F  4             192.168.10.4        DE:AD:BE:00:00:04
0x280-0x2FF  5             192.168.10.5        DE:AD:BE:00:00:05
0x300-0x37F  6             192.168.10.6        DE:AD:BE:00:00:06
0x380-0x3FF  7             192.168.10.7        DE:AD:BE:00:00:07
```

### Write Port Protocol (Control Plane)

Port B is used for runtime FIB updates (V2.0: via AXI4-Lite host interface).
For V1.0, writes are driven by the `fib_wr_en / fib_wr_addr / fib_wr_data`
ports at the top-level, which a test infrastructure or host AXI master drives.

```
Signal          Width   Description
fib_wr_en       1       Write enable (must be held for 1 cycle per write)
fib_wr_addr     10      Entry address [0..1023]
fib_wr_data     96      New entry value (see encoding above)
```

**Read-While-Write Behaviour:** Writing to an address that is simultaneously
being read by the lookup port produces the OLD value on the read port (write
takes effect at the next rising edge). This is safe because:
- Hash engine produces a lookup request only once per packet.
- A packet currently in-flight has already read its FIB entry.
- The 1-cycle write latency is invisible to the metadata pipeline.

---

## 2. Token Bucket Register File

The token bucket limiter uses **distributed LUT RAM** (not BRAM) because it
requires a read-modify-write in consecutive cycles, which BRAM cannot do without
a 2-cycle bypass mux. Each entry is a 32-bit counter.

| Parameter     | Value               |
|---------------|---------------------|
| Storage Type  | Distributed LUT RAM |
| Entries       | 8 (one per server)  |
| Word Width    | 32 bits             |
| Total         | 8 × 32 = 256 bits   |

### Token Bucket Address Map

```
Index  Server  Default Tokens  Reset Value
0      SRV-0   1,000,000       BUCKET_MAX
1      SRV-1   1,000,000       BUCKET_MAX
2      SRV-2   1,000,000       BUCKET_MAX
3      SRV-3   1,000,000       BUCKET_MAX
4      SRV-4   1,000,000       BUCKET_MAX
5      SRV-5   1,000,000       BUCKET_MAX
6      SRV-6   1,000,000       BUCKET_MAX
7      SRV-7   1,000,000       BUCKET_MAX
```

### Token Bucket Parameters (Verilog Parameters)

| Parameter      | Default     | Meaning                                    |
|----------------|-------------|--------------------------------------------|
| `BUCKET_MAX`   | 1,000,000   | Maximum tokens (burst capacity)            |
| `PACKET_COST`  | 1,500       | Tokens deducted per packet (≈ MTU bytes)   |
| `REFILL_RATE`  | 1,250       | Tokens added per refill event              |
| `REFILL_PERIOD`| 1,000       | Refill every N clocks (1kHz at 156 MHz → 156 kHz) |

Effective allowed rate per server:
```
Rate = REFILL_RATE × (clk_freq / REFILL_PERIOD) / PACKET_COST packets/sec
     = 1250 × (156,250,000 / 1000) / 1500
     ≈ 130,208 packets/sec per server
     ≈ 130k × 1500 B × 8 ≈ 1.56 Gbps per server
```

---

## 3. AXI4-Lite Control Plane Register Map (V2.0)

This section documents the planned register layout for the AXI4-Lite interface
that will allow a host CPU to update the FIB table at runtime without
recompiling the bitstream.

| Offset  | Register            | R/W | Description                          |
|---------|---------------------|-----|--------------------------------------|
| 0x0000  | CTRL_STATUS         | R   | [0]=pipeline_ready [1]=fifo_alarm    |
| 0x0004  | FIB_WRITE_ADDR      | W   | 10-bit FIB entry address [9:0]       |
| 0x0008  | FIB_WRITE_DATA_0    | W   | Entry bits [31:0]  (dst_ip)          |
| 0x000C  | FIB_WRITE_DATA_1    | W   | Entry bits [63:32] (dst_mac[31:0])   |
| 0x0010  | FIB_WRITE_DATA_2    | W   | Entry bits [95:64] (dst_mac[47:32] + flags) |
| 0x0014  | FIB_WRITE_COMMIT    | W   | Write 1 to atomically apply the staged entry |
| 0x0018  | STATS_PKT_COUNT     | R   | Total packets processed (saturating 32b) |
| 0x001C  | STATS_RATE_LIM      | R   | Rate-limited packet count            |
| 0x0020  | TOKEN_BUCKET_SRV(n) | R/W | Tokens remaining in server N bucket  |
|         | (n = 0x0020 + n×4)  |     | (n = 0..7)                           |

**Write Protocol:**
1. Write `FIB_WRITE_ADDR` with the target FIB slot.
2. Write `FIB_WRITE_DATA_0/1/2` with the 3-word entry.
3. Write `1` to `FIB_WRITE_COMMIT` — this triggers a single-cycle BRAM write.
   The commit register auto-clears after one clock cycle.

The staging registers ensure that a partially written entry is never visible
to the lookup port (atomicity guarantee).
