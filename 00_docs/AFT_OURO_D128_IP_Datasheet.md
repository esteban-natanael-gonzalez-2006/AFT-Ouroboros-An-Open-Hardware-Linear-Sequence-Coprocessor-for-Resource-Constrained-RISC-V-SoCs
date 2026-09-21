# AFT-OURO-D128-TOP: Microscalar Zero-DRAM Linear Attention IP Core

**Document Revision:** 1.0 (TRL 4 Validated)  
**Author:** Esteban Natanael Gonzalez (<esteban@aft-ouroboros.org>)  
**Division:** Silicon Engineering & Computational Physics — Project AFT Ouroboros  
**Date:** September 2026  
**License:** Proprietary RTL / Evaluation Netlist under NDA / Apache-2.0 Public Harness

---

## 1. Executive Summary

The **AFT-OURO-D128-TOP** is a specialized digital coprocessor IP core designed for **sub-watt edge artificial intelligence, microcontrollers, robotics, and low-latency digital signal processing**. 

Unlike conventional Transformer accelerators that suffer from the quadratic memory wall $\mathcal{O}(N^2)$ and require continuous multi-gigabyte external DRAM transfers for Key-Value caching, the AFT Ouroboros architecture executes an exact mathematical contraction in Clifford algebras $\text{Cl}(128)$ that reduces sequence processing to strictly **linear time $\mathcal{O}(N)$** with a completely static on-chip memory footprint.

The core integrates **128 parallel accumulators**, a **16-lane SIMD systolic multiplier-accumulator engine**, and **16 KiB of internal Block RAM (BRAM)**, enabling continuous sub-watt operation with **zero external DRAM bandwidth consumption**.

---

## 2. Key Architecture Features

* **Zero-DRAM Architecture:** Working set (weights + state) resides 100% inside on-chip SRAM/BRAM ($\le 18\text{ KiB}$ total active footprint). Eliminates off-chip I/O power dissipation.
* **Deterministic Dual-Phase Latency:**
  * **Phase 1 (Linear Context Accumulation):** Ingests $N$ tokens at a sustained throughput of **1 token per clock cycle** ($250\text{ Mtokens/s}$ @ $250\text{ MHz}$).
  * **Phase 2 (Constant-Time Global Contraction):** Executes the matrix-vector transformation $\mathbf{Z} = \Gamma \Psi$ and scalar contraction $S = \Psi^\top \mathbf{Z}$ in a deterministic constant latency of **1,280 clock cycles ($5.12\ \mu\text{s}$ @ $250\text{ MHz}$)**, completely independent of sequence length $N$.
* **Standard Industrial Interconnect:** Standard AXI4-Stream slave input (1024-bit wide for $D=128\times\text{INT8}$) and AXI4-Stream master output (64-bit scalar energy).
* **Hardware-Verified Arithmetic Precision:** Evaluated with 48-bit intermediate MAC registers (DSP48E2 native mapping) and 64-bit output accumulators, achieving **0-bit discrepancy (exact integer identity $\Delta = 0$)** against reference software.

---

## 3. Signal Interface and Pinout Specification

| Signal Name | Direction | Bitwidth | Protocol | Description |
| :--- | :---: | :---: | :---: | :--- |
| `aclk` | Input | 1 | Clock | Primary core clock (Target: $250\text{ MHz}$ UltraScale+, $150-200\text{ MHz}$ 7-Series). |
| `aresetn` | Input | 1 | Reset | Active-low synchronous system reset. |
| **AXI4-Stream Slave Interface (Token Streaming Input)** | | | | |
| `s_axis_tdata` | Input | 1024 | AXI4-Stream | Unpacked 128-element token vector $\psi_t$ ($128 \times 8\text{-bit}$ signed integers). |
| `s_axis_tvalid` | Input | 1 | AXI4-Stream | Handshake signal; indicates that `s_axis_tdata` is valid. |
| `s_axis_tready` | Output | 1 | AXI4-Stream | Core readiness signal; asserted continuously during accumulation. |
| `s_axis_tlast` | Input | 1 | AXI4-Stream | Packet boundary; indicates the final token ($t = N - 1$) of the sequence. |
| **AXI4-Stream Master Interface (Scalar Energy Contraction Output)** | | | | |
| `m_axis_tdata` | Output | 64 | AXI4-Stream | Computed scalar energy contraction $S_{\text{total}} = \Psi^\top \Gamma \Psi$ (64-bit signed). |
| `m_axis_tvalid` | Output | 1 | AXI4-Stream | Handshake signal; asserted upon completion of global contraction. |
| `m_axis_tready` | Input | 1 | AXI4-Stream | Downstream receiver readiness signal. |
| `m_axis_tlast` | Output | 1 | AXI4-Stream | Packet boundary; co-asserted with `m_axis_tvalid`. |

---

## 4. Latency and Throughput Breakdown

Operational timing follows the exact affine model $T(N) = T_0 + cN$ established in the project's empirical evidence matrix:

| Pipeline Stage | Cycles | Latency @ 250 MHz ($T_{\text{clk}} = 4.0\text{ ns}$) | Description |
| :--- | :---: | :---: | :--- |
| **1. Stream Ingestion (`s_axis`)** | $N$ | $N \times 4.0\text{ ns}$ | 1 token/cycle streaming accumulation: $\Psi = \sum_{t=0}^{N-1} \psi_t$. |
| **2. Local State Transfer** | $128$ | $0.512\ \mu\text{s}$ | Internal transfer of $\Psi$ registers to the GEMV execution buffer. |
| **3. Pipelined GEMV ($\mathbf{Z} = \Gamma \Psi$)** | $1,024$ | $4.096\ \mu\text{s}$ | 16-lane SIMD matrix multiplier ($128\text{ rows} \times 8\text{ cycles/row}$). |
| **4. Scalar Contraction ($S = \Psi^\top \mathbf{Z}$)** | $128$ | $0.512\ \mu\text{s}$ | Pipelined 64-bit dot product and output emission. |
| **Total Post-Sequence Contraction ($T_0$)** | **$1,280$** | **$5.120\ \mu\text{s}$** | **Constant hardware latency, independent of $N$.** |

---

## 5. Physical Synthesis and Resource Utilization

Synthesized and validated with **Yosys 0.69** for Xilinx 7-Series / Zynq / UltraScale+ target architectures:

| Primitive Type | Hardware Cell | Instances | Target: Kria KV260 (XCK26) | Target: PYNQ-Z2 (XC7Z020) |
| :--- | :--- | :---: | :---: | :---: |
| **DSP Slices** | `DSP48E1` / `DSP48E2` | **38** | $3.04\%$ (of 1,248) | $17.27\%$ (of 220) |
| **Flip-Flops (Registers)** | `FDCE` / `FDRE` | **18,798** | $8.02\%$ (of 234,240) | $17.67\%$ (of 106,400) |
| **Look-Up Tables (LUTs)** | `LUT2` .. `LUT6` | **21,640**\* | $18.48\%$ (of 117,120) | $40.68\%$ (of 53,200) |
| **Fast Carry Chains** | `CARRY4` | **1,094** | $3.73\%$ (of 29,280) | $8.22\%$ (of 13,300) |
| **Block RAM** | `RAMB36E1` | **4** | $2.77\%$ (of 144) | $2.86\%$ (of 140) |

*\*Note: LUT count includes distributed ROM mapping for matrix $\Gamma$ under Yosys; reduces to $\approx 14,000\text{ LUTs}$ under AMD Vivado with native 4x BRAM36K inference.*

---

## 6. Verification and Technological Readiness (TRL 4)

* **Cycle-Accurate Simulation:** Verified bit-for-bit with **Icarus Verilog (`iverilog`)** against golden vectors generated from verified C reference code (`gen_golden_vectors.c`).
* **Test Sequences Evaluated:** $N \in \{8, 32, 64, 128, 256\}$ tokens across dynamic output ranges from $-6.14 \times 10^9$ to $+1.58 \times 10^{10}$.
* **Discrepancy:** **Exactly 0 discrepancies across all test vectors.**
* **Cryptographic Integrity:** Golden stimulus and reference vectors verified via SHA-256 hashes recorded in `05_artifacts_checkpoints/metadata/golden_vectors_hashes.sha256`.

---

## 7. Licensing and Commercial Availability

The **AFT-OURO-D128-TOP** core is available for commercial licensing, evaluation, and silicon co-development under the following models:

1. **Evaluation Netlist License:** Pre-synthesized, encrypted netlist / DCP for Vivado evaluation on AMD Kria KV260 or PYNQ-Z2.
2. **Synthesizable RTL Source License:** Full SystemVerilog source code, self-checking testbenches, Vivado batch synthesis scripts, and golden reference vector generators.
3. **Custom Architectural Tailoring:** Parameterized scaling for custom dimension spaces ($D = 64, 256, 512, 1024$), variable SIMD parallelism (16 to 64 lanes), and specialized foundry process nodes (TSMC, GlobalFoundries, SkyWater 130nm).

**Direct Inquiries & Technical Transfer:**  
Esteban Natanael Gonzalez  
Principal Architect & Systems Engineer  
Project AFT Ouroboros — Salta, Argentina  
Email: `esteban@aft-ouroboros.org` | Web: `https://aft-ouroboros.org`
