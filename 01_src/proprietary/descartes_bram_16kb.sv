`timescale 1ns / 1ps

module descartes_bram_16kb #(
    parameter int ADDR_WIDTH = 10,       // 1024 líneas
    parameter int DATA_WIDTH = 128       // 16 bytes por línea (16 KiB total)
)(
    input  logic                             clk,
    input  logic [ADDR_WIDTH - 1 : 0]        addr,
    output logic [DATA_WIDTH - 1 : 0]        rdata
);

    // 1024 palabras de 128 bits (16 KiB)
    (* ram_style = "block" *) logic [DATA_WIDTH - 1 : 0] ram [0 : (1 << ADDR_WIDTH) - 1];

    // Carga de la matriz Gamma pre-empaquetada en líneas de 16 bytes
    initial begin
        $readmemh("matrix_gamma_packed128.hex", ram);
    end

    always_ff @(posedge clk) begin
        rdata <= ram[addr];
    end

endmodule
