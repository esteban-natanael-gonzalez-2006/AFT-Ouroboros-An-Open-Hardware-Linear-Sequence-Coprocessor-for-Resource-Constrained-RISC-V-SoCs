`timescale 1ns / 1ps

module descartes_operator_top #(
    parameter int D = 128,
    parameter int IN_WIDTH = 8,
    parameter int ACC_WIDTH = 32,
    parameter int OUT_WIDTH = 64
)(
    input  logic                                  aclk,
    input  logic                                  aresetn,

    // Interfaz AXI4-Stream Slave (Entrada continua de tokens)
    input  logic                                  s_axis_tvalid,
    output logic                                  s_axis_tready,
    input  logic [(D * IN_WIDTH) - 1 : 0]         s_axis_tdata,
    input  logic                                  s_axis_tlast,

    // Interfaz AXI4-Stream Master (Emisión del resultado escalar)
    output logic                                  m_axis_tvalid,
    input  logic                                  m_axis_tready,
    output logic signed [OUT_WIDTH - 1 : 0]       m_axis_tdata,
    output logic                                  m_axis_tlast
);

    logic clr_acc;
    logic acc_busy, acc_done;
    logic [15:0] seq_len;
    logic [6:0] psi_rd_addr;
    logic signed [ACC_WIDTH - 1 : 0] psi_rd_data;

    logic gemv_start, gemv_busy, gemv_done;
    logic [9:0] gamma_bram_addr;
    logic signed [127:0] gamma_bram_rdata;
    logic signed [OUT_WIDTH - 1 : 0] s_total_raw;

    // FSM de control del Core
    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        ACCUMULATE  = 2'b01,
        CONTRACTION = 2'b10,
        OUTPUT_RES  = 2'b11
    } top_fsm_t;

    top_fsm_t state;

    // 1. Unidad de acumulación lineal O(N)
    descartes_acc_unit #(
        .D(D), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) u_acc (
        .clk(aclk),
        .rst_n(aresetn),
        .clr_acc(clr_acc),
        .acc_busy(acc_busy),
        .acc_done(acc_done),
        .seq_len_out(seq_len),
        .s_axis_tvalid(s_axis_tvalid && (state == ACCUMULATE || state == IDLE)),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .psi_wide_out(),
        .psi_valid(),
        .read_addr(psi_rd_addr),
        .read_data(psi_rd_data)
    );

    // 2. Memoria BRAM interna para Gamma (16 KiB)
    descartes_bram_16kb #(
        .ADDR_WIDTH(10), .DATA_WIDTH(128)
    ) u_gamma_bram (
        .clk(aclk),
        .addr(gamma_bram_addr),
        .rdata(gamma_bram_rdata)
    );

    // 3. Motor GEMV y reducción escalar
    descartes_gemv_engine #(
        .D(D), .SIMD_WIDTH(16), .IN_WIDTH(IN_WIDTH),
        .ACC_WIDTH(ACC_WIDTH), .OUT_WIDTH(OUT_WIDTH)
    ) u_gemv (
        .clk(aclk),
        .rst_n(aresetn),
        .start(gemv_start),
        .busy(gemv_busy),
        .done(gemv_done),
        .psi_rd_addr(psi_rd_addr),
        .psi_rd_data(psi_rd_data),
        .gamma_bram_addr(gamma_bram_addr),
        .gamma_bram_rdata(gamma_bram_rdata),
        .s_total_out(s_total_raw)
    );

    // Control de flujo AXI y orquestación
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state         <= IDLE;
            clr_acc       <= 1'b0;
            gemv_start    <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= '0;
            m_axis_tlast  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    clr_acc       <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    if (s_axis_tvalid && s_axis_tready) begin
                        state <= ACCUMULATE;
                    end
                end

                ACCUMULATE: begin
                    if (acc_done) begin
                        state      <= CONTRACTION;
                        gemv_start <= 1'b1;
                    end
                end

                CONTRACTION: begin
                    gemv_start <= 1'b0;
                    if (gemv_done) begin
                        state         <= OUTPUT_RES;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tdata  <= s_total_raw;
                        m_axis_tlast  <= 1'b1;
                    end
                end

                OUTPUT_RES: begin
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                        clr_acc       <= 1'b1; // Reset para siguiente secuencia
                        state         <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
