`timescale 1ns / 1ps

module tb_descartes_acc_unit;

    localparam int D = 128;
    localparam int IN_WIDTH = 8;
    localparam int ACC_WIDTH = 32;
    localparam real CLK_PERIOD = 4.0; // 250 MHz

    logic clk, rst_n, clr_acc, acc_busy, acc_done;
    logic [15:0] seq_len_out;
    logic s_axis_tvalid, s_axis_tready, s_axis_tlast, psi_valid;
    logic [(D * IN_WIDTH) - 1 : 0] s_axis_tdata;
    logic [(D * ACC_WIDTH) - 1 : 0] psi_wide_out;
    logic [6:0] read_addr;
    logic signed [ACC_WIDTH - 1 : 0] read_data;

    descartes_acc_unit #(
        .D(D), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc), .acc_busy(acc_busy),
        .acc_done(acc_done), .seq_len_out(seq_len_out), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tdata(s_axis_tdata), .s_axis_tlast(s_axis_tlast),
        .psi_wide_out(psi_wide_out), .psi_valid(psi_valid), .read_addr(read_addr), .read_data(read_data)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    integer file_stim, file_gold, r_scan, seq_idx, d_idx, errors_total = 0;
    logic tlast_file;
    logic [(D * IN_WIDTH) - 1 : 0] token_data_file;
    logic signed [ACC_WIDTH - 1 : 0] exp_psi [0 : D - 1];
    logic token_active;

    initial begin
        rst_n = 1'b0; clr_acc = 1'b0; s_axis_tvalid = 1'b0; s_axis_tdata = '0; s_axis_tlast = 1'b0; read_addr = '0;
        #(CLK_PERIOD * 5); rst_n = 1'b1; #(CLK_PERIOD * 5);

        file_stim = $fopen("stimulus_tokens.hex", "r");
        file_gold = $fopen("golden_acc_psi.hex", "r");
        if (!file_stim || !file_gold) begin
            $display("[-] ERROR: No se pudieron abrir stimulus_tokens.hex o golden_acc_psi.hex.");
            $finish;
        end

        for (seq_idx = 0; seq_idx < 5; seq_idx = seq_idx + 1) begin
            @(posedge clk); clr_acc = 1'b1;
            @(posedge clk); clr_acc = 1'b0;

            token_active = 1'b1;
            while (token_active) begin
                @(posedge clk);
                r_scan = $fscanf(file_stim, "%d %h\n", tlast_file, token_data_file);
                if (r_scan == 2) begin
                    s_axis_tvalid <= 1'b1;
                    s_axis_tdata  <= token_data_file;
                    s_axis_tlast  <= tlast_file;
                    if (tlast_file) token_active = 1'b0;
                end else begin
                    token_active = 1'b0;
                end
            end

            @(posedge clk); s_axis_tvalid <= 1'b0; s_axis_tlast <= 1'b0;
            if (!acc_done) @(posedge acc_done);

            for (d_idx = 0; d_idx < D; d_idx = d_idx + 1) begin
                r_scan = $fscanf(file_gold, "%h\n", exp_psi[d_idx]);
            end

            for (d_idx = 0; d_idx < D; d_idx = d_idx + 1) begin
                read_addr = d_idx[6:0]; #1;
                if (read_data !== exp_psi[d_idx]) begin
                    $display("[-] Discrepancia Seq %0d Dim %0d: RTL=%h EXP=%h", seq_idx, d_idx, read_data, exp_psi[d_idx]);
                    errors_total = errors_total + 1;
                end
            end
            if (errors_total == 0) begin
                $display("[OK] Secuencia %0d (N=%0d): 128 dimensiones verificadas bit a bit.", seq_idx, seq_len_out);
            end
        end

        $fclose(file_stim); $fclose(file_gold);
        if (errors_total == 0) $display("\n[+] RESULTADO: SIMULACION IVERILOG EXITOSA. 0 DISCREPANCIAS.\n");
        $finish;
    end

endmodule
