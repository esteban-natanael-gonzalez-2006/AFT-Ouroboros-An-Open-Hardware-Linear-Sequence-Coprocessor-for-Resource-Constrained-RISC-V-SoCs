`timescale 1ns / 1ps

module tb_descartes_top;

    localparam int D = 128;
    localparam int IN_WIDTH = 8;
    localparam int OUT_WIDTH = 64;
    localparam real CLK_PERIOD = 4.0; // 250 MHz

    logic aclk, aresetn;
    logic s_axis_tvalid, s_axis_tready, s_axis_tlast;
    logic [(D * IN_WIDTH) - 1 : 0] s_axis_tdata;
    logic m_axis_tvalid, m_axis_tready, m_axis_tlast;
    logic signed [OUT_WIDTH - 1 : 0] m_axis_tdata;

    reg signed [OUT_WIDTH - 1 : 0] exp_s_total_mem [0 : 4];

    descartes_operator_top #(
        .D(D), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(32), .OUT_WIDTH(OUT_WIDTH)
    ) uut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast)
    );

    initial aclk = 0;
    always #(CLK_PERIOD / 2.0) aclk = ~aclk;

    integer file_stim, r_scan, seq, errors = 0;
    logic tlast_file, token_active;
    logic [(D * IN_WIDTH) - 1 : 0] token_data_file;
    reg signed [OUT_WIDTH - 1 : 0] exp_val;

    initial begin
        aresetn = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = '0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;

        #(CLK_PERIOD * 5);
        aresetn = 1'b1;
        #(CLK_PERIOD * 5);

        $readmemh("golden_s_total.hex", exp_s_total_mem);
        file_stim = $fopen("stimulus_tokens.hex", "r");
        if (!file_stim) begin
            $display("[-] ERROR: No se pudo abrir stimulus_tokens.hex");
            $finish;
        end

        $display("=================================================================================");
        $display("  AFT OUROBOROS: TESTBENCH INTEGRAL TOP-LEVEL (AXI4-STREAM / BRAM / 250 MHz)");
        $display("=================================================================================");

        for (seq = 0; seq < 5; seq = seq + 1) begin
            exp_val = exp_s_total_mem[seq];
            token_active = 1'b1;

            // Inyectar secuencia completa de tokens a través del bus AXI4-Stream
            while (token_active) begin
                @(posedge aclk);
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

            @(posedge aclk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;

            // Esperar resultado en el bus Master AXI4-Stream
            @(posedge m_axis_tvalid);
            #1;

            if (m_axis_tdata !== exp_val) begin
                $display("[-] DISCREPANCIA Secuencia %0d: RTL=%0d | ESPERADO=%0d", 
                         seq, m_axis_tdata, exp_val);
                errors = errors + 1;
            end else begin
                $display("[OK] Secuencia %0d completada con exito en AXI-Stream: %0d", 
                         seq, m_axis_tdata);
            end

            #(CLK_PERIOD * 10);
        end

        $fclose(file_stim);
        $display("---------------------------------------------------------------------------------");
        if (errors == 0) begin
            $display("[+] RESULTADO: SIMULACION INTEGRAL DEL TOP-LEVEL EXITOSA. 0 DISCREPANCIAS.");
        end else begin
            $display("[-] RESULTADO: FALLO CON %0d DISCREPANCIAS.", errors);
        end
        $display("=================================================================================");
        $finish;
    end

endmodule
