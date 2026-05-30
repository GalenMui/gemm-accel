`timescale 1ns / 1ps

module tile_buffer #(
    parameter int DATA_W = 8,
    parameter int ROWS = 2,
    parameter int COLS = 2,
    parameter int DEPTH = ROWS * COLS,
    parameter int ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
    input  logic                          clk,
    input  logic                          rst,
    input  logic                          clear,
    input  logic                          write_en,
    input  logic [ADDR_W-1:0]             write_addr,
    input  logic [DATA_W-1:0]             write_data,
    output logic [ROWS*COLS*DATA_W-1:0]   data_flat
);

    logic [DATA_W-1:0] mem [0:DEPTH-1];

    integer idx;
    genvar flat_idx;

    generate
        for (flat_idx = 0; flat_idx < DEPTH; flat_idx++) begin : gen_flatten
            assign data_flat[(flat_idx * DATA_W) +: DATA_W] = mem[flat_idx];
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            for (idx = 0; idx < DEPTH; idx++) begin
                mem[idx] <= '0;
            end
        end else if (write_en) begin
            mem[write_addr] <= write_data;
        end
    end

endmodule
