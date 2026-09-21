`timescale 1ns / 1ps

module descartes_gemv_engine #(
    parameter int D = 128,
    parameter int SIMD_WIDTH = 16,
    parameter int IN_WIDTH = 8,
    parameter int ACC_WIDTH = 32,
    parameter int OUT_WIDTH = 64
)(
    input  logic                                  clk,
    input  logic                                  rst_n,
    input  logic                                  start,
    output logic                                  busy,
    output logic                                  done,

    // Lectura del vector Psi desde descartes_acc_unit
    output logic [6:0]                            psi_rd_addr,
    input  logic signed [ACC_WIDTH - 1 : 0]       psi_rd_data,

    // Interfaz BRAM para matriz Gamma (16 bytes = 128 bits por ciclo, latencia = 1 clk)
    output logic [9:0]                            gamma_bram_addr,
    input  logic signed [(SIMD_WIDTH * IN_WIDTH) - 1 : 0] gamma_bram_rdata,

    // Salida escalar S_total = Psi^T * Gamma * Psi
    output logic signed [OUT_WIDTH - 1 : 0]       s_total_out
);

    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        LOAD_PSI    = 3'b001,
        COMPUTE_GEMV= 3'b010,
        COMPUTE_DOT = 3'b011,
        DONE_ST     = 3'b100
    } state_t;

    state_t state;

    logic signed [ACC_WIDTH - 1 : 0] psi_local [0 : D - 1];
    logic signed [47:0] z_reg [0 : D - 1];

    // Pipeline Etapa 0: Punteros de petición a BRAM
    logic [6:0] fetch_row;
    logic [2:0] fetch_blk;
    logic       fetch_active;

    // Pipeline Etapa 1: Punteros alineados con la llegada de rdata de BRAM
    logic [6:0] exec_row;
    logic [2:0] exec_blk;
    logic       exec_valid;

    logic [6:0] dot_idx;
    logic signed [47:0] mac_acc;
    logic signed [OUT_WIDTH - 1 : 0] s_acc;

    assign busy  = (state != IDLE);
    assign done  = (state == DONE_ST);
    assign s_total_out = s_acc;
    assign gamma_bram_addr = {fetch_row, fetch_blk};

    // Desempaquetado continuo de los 16 bytes de BRAM
    wire signed [IN_WIDTH - 1 : 0] gamma_slice [0 : SIMD_WIDTH - 1];
    genvar gi;
    generate
        for (gi = 0; gi < SIMD_WIDTH; gi = gi + 1) begin : gen_gamma_unpack
            assign gamma_slice[gi] = gamma_bram_rdata[(gi * IN_WIDTH) +: IN_WIDTH];
        end
    endgenerate

    // Multiplicadores SIMD alineados con el ciclo de llegada de BRAM
    logic signed [47:0] simd_mult [0 : SIMD_WIDTH - 1];
    logic signed [47:0] simd_sum;

    integer s;
    always_comb begin
        simd_sum = 48'sd0;
        for (s = 0; s < SIMD_WIDTH; s = s + 1) begin
            simd_mult[s] = $signed(gamma_slice[s]) * $signed(psi_local[(exec_blk * SIMD_WIDTH) + s]);
            simd_sum = simd_sum + simd_mult[s];
        end
    end

    integer k;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            psi_rd_addr  <= '0;
            fetch_row    <= '0;
            fetch_blk    <= '0;
            fetch_active <= 1'b0;
            exec_row     <= '0;
            exec_blk     <= '0;
            exec_valid   <= 1'b0;
            dot_idx      <= '0;
            mac_acc      <= '0;
            s_acc        <= '0;
            for (k = 0; k < D; k = k + 1) begin
                psi_local[k] <= '0;
                z_reg[k]     <= '0;
            end
        end else begin
            case (state)
                IDLE: begin
                    fetch_active <= 1'b0;
                    exec_valid   <= 1'b0;
                    if (start) begin
                        state       <= LOAD_PSI;
                        psi_rd_addr <= '0;
                    end
                end

                LOAD_PSI: begin
                    psi_local[psi_rd_addr] <= psi_rd_data;
                    if (psi_rd_addr == 7'd127) begin
                        state        <= COMPUTE_GEMV;
                        fetch_row    <= '0;
                        fetch_blk    <= '0;
                        fetch_active <= 1'b1;
                        exec_valid   <= 1'b0;
                        mac_acc      <= '0;
                    end else begin
                        psi_rd_addr <= psi_rd_addr + 7'd1;
                    end
                end

                COMPUTE_GEMV: begin
                    // Etapa 0: Generar dirección hacia BRAM
                    if (fetch_active) begin
                        if (fetch_blk == 3'd7) begin
                            fetch_blk <= '0;
                            if (fetch_row == 7'd127) begin
                                fetch_active <= 1'b0;
                            end else begin
                                fetch_row <= fetch_row + 7'd1;
                            end
                        end else begin
                            fetch_blk <= fetch_blk + 3'd1;
                        end
                    end

                    // Retardo de 1 ciclo: Sincronización de coordenadas con la salida de BRAM
                    exec_row   <= fetch_row;
                    exec_blk   <= fetch_blk;
                    exec_valid <= fetch_active;

                    // Etapa 1: Acumulación MAC con datos válidos de BRAM
                    if (exec_valid) begin
                        if (exec_blk == 3'd0) begin
                            mac_acc <= simd_sum;
                        end else begin
                            mac_acc <= mac_acc + simd_sum;
                        end

                        if (exec_blk == 3'd7) begin
                            z_reg[exec_row] <= (exec_blk == 3'd0 ? 48'sd0 : mac_acc) + simd_sum;
                            if (exec_row == 7'd127) begin
                                state   <= COMPUTE_DOT;
                                dot_idx <= '0;
                                s_acc   <= '0;
                            end
                        end
                    end
                end

                COMPUTE_DOT: begin
                    s_acc <= s_acc + ($signed(psi_local[dot_idx]) * $signed(z_reg[dot_idx]));
                    if (dot_idx == 7'd127) begin
                        state <= DONE_ST;
                    end else begin
                        dot_idx <= dot_idx + 7'd1;
                    end
                end

                DONE_ST: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
