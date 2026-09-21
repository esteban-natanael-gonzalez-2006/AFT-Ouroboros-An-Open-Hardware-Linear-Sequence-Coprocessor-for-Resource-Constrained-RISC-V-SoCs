`timescale 1ns / 1ps

module tb_descartes_gemv_engine;

    localparam int D = 128;
    localparam int SIMD_WIDTH = 16;
    localparam int IN_WIDTH = 8;
    localparam int ACC_WIDTH = 32;
    localparam int OUT_WIDTH = 64;
    localparam real CLK_PERIOD = 4.0; // 250 MHz

    logic clk, rst_n, start, busy, done;
    logic [6:0] psi_rd_addr;
    logic signed [ACC_WIDTH - 1 : 0] psi_rd_data;
    logic [9:0] gamma_bram_addr;
    logic signed [(SIMD_WIDTH * IN_WIDTH) - 1 : 0] gamma_bram_rdata;
    logic signed [OUT_WIDTH - 1 : 0] s_total_out;

    // Arreglos de memoria planos cargados nativamente con $readmemh
    reg signed [IN_WIDTH - 1 : 0]  gamma_flat [0 : (D * D) - 1];
    reg signed [ACC_WIDTH - 1 : 0] psi_flat   [0 : (5 * D) - 1];
    reg signed [OUT_WIDTH - 1 : 0] exp_s_total_mem [0 : 4];

    reg [2:0] current_seq;

    descartes_gemv_engine #(
        .D(D), .SIMD_WIDTH(SIMD_WIDTH), .IN_WIDTH(IN_WIDTH),
        .ACC_WIDTH(ACC_WIDTH), .OUT_WIDTH(OUT_WIDTH)
    ) uut (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
        .psi_rd_addr(psi_rd_addr), .psi_rd_data(psi_rd_data),
        .gamma_bram_addr(gamma_bram_addr), .gamma_bram_rdata(gamma_bram_rdata),
        .s_total_out(s_total_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    assign psi_rd_data = psi_flat[(current_seq * D) + psi_rd_addr];

    wire [6:0] g_row = gamma_bram_addr[9:3];
    wire [2:0] g_blk = gamma_bram_addr[2:0];

    genvar b;
    generate
        for (b = 0; b < SIMD_WIDTH; b = b + 1) begin : gen_bram_read
            assign gamma_bram_rdata[(b * IN_WIDTH) +: IN_WIDTH] = 
                gamma_flat[(g_row * D) + (g_blk * SIMD_WIDTH) + b];
        end
    endgenerate

    integer seq, errors = 0;
    reg signed [OUT_WIDTH - 1 : 0] exp_s;

    initial begin
        rst_n = 1'b0; start = 1'b0; current_seq = 0;
        #(CLK_PERIOD * 5); rst_n = 1'b1; #(CLK_PERIOD * 5);

        // Carga nativa con $readmemh (cero dependencias de $fscanf)
        $readmemh("matrix_gamma.hex", gamma_flat);
        $readmemh("golden_acc_psi.hex", psi_flat);
        $readmemh("golden_s_total.hex", exp_s_total_mem);

        $display("=================================================================================");
        $display("  AFT OUROBOROS: TESTBENCH MOTOR GEMV DESCARTES (16 LANES SIMD / 250 MHz)");
        $display("=================================================================================");

        for (seq = 0; seq < 5; seq = seq + 1) begin
            current_seq = seq[2:0];
            exp_s = exp_s_total_mem[seq];

            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            @(posedge done);
            #1;

            if (s_total_out !== exp_s) begin
                $display("[-] DISCREPANCIA Seq %0d: RTL S_total=%0d | EXP S_total=%0d", 
                         seq, s_total_out, exp_s);
                errors = errors + 1;
            end else begin
                $display("[OK] Secuencia %0d: S_total coincidente bit a bit (%0d).", 
                         seq, s_total_out);
            end
            #(CLK_PERIOD * 5);
        end

        $display("---------------------------------------------------------------------------------");
        if (errors == 0) begin
            $display("[+] RESULTADO: SIMULACION MOTOR GEMV DESCARTES EXITOSA. 0 DISCREPANCIAS.");
        end else begin
            $display("[-] RESULTADO: FALLO CON %0d DISCREPANCIAS.", errors);
        end
        $display("=================================================================================");
        $finish;
    end

endmodule
