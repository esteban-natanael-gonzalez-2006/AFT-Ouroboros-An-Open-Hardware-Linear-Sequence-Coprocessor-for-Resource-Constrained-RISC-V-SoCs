`timescale 1ns / 1ps

module descartes_acc_unit #(
    parameter int D = 128,
    parameter int IN_WIDTH = 8,
    parameter int ACC_WIDTH = 32
)(
    input  logic                                  clk,
    input  logic                                  rst_n,
    input  logic                                  clr_acc,
    output logic                                  acc_busy,
    output logic                                  acc_done,
    output logic [15:0]                           seq_len_out,

    input  logic                                  s_axis_tvalid,
    output logic                                  s_axis_tready,
    input  logic [(D * IN_WIDTH) - 1 : 0]         s_axis_tdata,
    input  logic                                  s_axis_tlast,

    output logic [(D * ACC_WIDTH) - 1 : 0]        psi_wide_out,
    output logic                                  psi_valid,

    input  logic [6:0]                            read_addr,
    output logic signed [ACC_WIDTH - 1 : 0]       read_data
);

    logic signed [ACC_WIDTH - 1 : 0] acc_reg [0 : D - 1];
    logic signed [ACC_WIDTH - 1 : 0] locked_reg [0 : D - 1];
    logic [15:0] token_count;
    logic        active;
    logic        done_pulse;

    assign s_axis_tready = rst_n;
    assign acc_busy      = active;
    assign acc_done      = done_pulse;
    assign seq_len_out   = token_count;
    assign psi_valid     = done_pulse;
    assign read_data     = locked_reg[read_addr];

    genvar g;
    generate
        for (g = 0; g < D; g = g + 1) begin : gen_wide_out
            assign psi_wide_out[(g * ACC_WIDTH) +: ACC_WIDTH] = locked_reg[g];
        end
    endgenerate

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            token_count <= 16'd0; active <= 1'b0; done_pulse <= 1'b0;
            for (i = 0; i < D; i = i + 1) begin
                acc_reg[i] <= '0; locked_reg[i] <= '0;
            end
        end else begin
            done_pulse <= 1'b0;
            if (clr_acc) begin
                token_count <= 16'd0; active <= 1'b0;
                for (i = 0; i < D; i = i + 1) acc_reg[i] <= '0;
            end else if (s_axis_tvalid && s_axis_tready) begin
                active      <= 1'b1;
                token_count <= token_count + 16'd1;
                for (i = 0; i < D; i = i + 1) begin
                    acc_reg[i] <= acc_reg[i] + $signed(s_axis_tdata[(i * IN_WIDTH) +: IN_WIDTH]);
                end
                if (s_axis_tlast) begin
                    active     <= 1'b0;
                    done_pulse <= 1'b1;
                    for (i = 0; i < D; i = i + 1) begin
                        locked_reg[i] <= acc_reg[i] + $signed(s_axis_tdata[(i * IN_WIDTH) +: IN_WIDTH]);
                    end
                end
            end
        end
    end

endmodule
