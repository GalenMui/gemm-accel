`timescale 1ns / 1ps

module scratchpad #(
    parameter int DATA_W = 8,
    parameter int DEPTH = 4096,
    parameter int ADDR_W = $clog2(DEPTH),
    parameter RAM_STYLE = "block"
) (
    input  logic              clk,
    input  logic              a_en,
    input  logic              a_we,
    input  logic [ADDR_W-1:0] a_addr,
    input  logic [DATA_W-1:0] a_wdata,
    output logic [DATA_W-1:0] a_rdata,
    input  logic              b_en,
    input  logic              b_we,
    input  logic [ADDR_W-1:0] b_addr,
    input  logic [DATA_W-1:0] b_wdata,
    output logic [DATA_W-1:0] b_rdata
);

    // Vivado-friendly true dual-port RAM style for host-side access plus
    // accelerator-side access without forcing large arrays into registers.
    (* ram_style = RAM_STYLE *) logic [DATA_W-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (a_en) begin
            if (a_we) begin
                mem[a_addr] <= a_wdata;
            end
            a_rdata <= mem[a_addr];
        end
    end

    always_ff @(posedge clk) begin
        if (b_en) begin
            if (b_we) begin
                mem[b_addr] <= b_wdata;
            end
            b_rdata <= mem[b_addr];
        end
    end

endmodule
