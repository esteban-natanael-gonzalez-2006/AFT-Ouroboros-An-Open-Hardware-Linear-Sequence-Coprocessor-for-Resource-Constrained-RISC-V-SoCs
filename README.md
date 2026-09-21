# AFT-Ouroboros: An Open-Hardware Linear Sequence Coprocessor for Resource-Constrained RISC-V SoCs

[![Hardware License](https://img.shields.io/badge/License-Solderpad_v2.1-blue.svg)](https://solderpad.org/licenses/SHL-2.1/)
[![Software License](https://img.shields.io/badge/License-Apache_2.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![TRL Level](https://img.shields.io/badge/TRL-4_Validated-orange.svg)]()

AFT-Ouroboros is an open-source digital coprocessor designed for sub-watt linear-time sequence processing in resource-constrained embedded systems and open RISC-V SoCs.

## Key Technical Specifications
- **Asymptotic Complexity:** Linear $\mathcal{O}(N)$ interaction scaling via global bilinear contraction over Clifford algebras $\text{Cl}(128)$ for fixed dimension $D=128$.
- **Deterministic Latency:** $N$ cycles for streaming ingestion, followed by a constant-time global contraction of exactly 1,280 clock cycles ($5.12\ \mu\text{s}$ at $250\text{ MHz}$), strictly independent of sequence length $N$.
- **Zero External-DRAM Working Set:** The complete parameter matrix $\Gamma$ ($16\text{ KiB}$ INT8) and accumulator state reside entirely within on-chip Block RAM/SRAM.
- **Physical Synthesis (Xilinx 7-Series / Yosys 0.69):** 38 `DSP48E1` slices, 18,798 Flip-Flops, $F_{\max} \ge 200\text{ MHz}$.
- **Verification:** Cycle-accurate SystemVerilog RTL verified with 0 bit-level discrepancies against analytical C models across sequences $N \in \{8, 32, 64, 128, 256\}$.

## Repository Taxonomy

```text
.
├── 00_docs/                  # Spec, datasheets & white papers
├── 01_src/
│   ├── proprietary/          # RTL core (Acc, GEMV, BRAM, Top)
│   └── public/               # Testbenches, stimuli & golden vectors
├── 02_benchmarks/            # EDA synthesis scripts & logs
├── 03_data/                  # Curated calibration datasets
└── aft_fpga_sim/.            # Hashes, metadata & checkpoints
```

## Documentation References
- [AFT-OURO-D128-TOP Datasheet](00_docs/AFT_OURO_D128_IP_Datasheet.md)
- [Architecture Specification V9.5](00_docs/architecture_spec_v9.5.md)
- [NLnet Restack Grant Proposal](00_docs/NLnet_Restack_Grant_Proposal_AFT_Ouroboros.md)

## Author & Contact
- **Principal Investigator:** Esteban Natanael Gonzalez (<esteban@aft-ouroboros.org>)
- **Entity:** Project AFT Ouroboros — Silicon Engineering & Computational Physics
- **Website:** [https://aft-ouroboros.org](https://aft-ouroboros.org)
