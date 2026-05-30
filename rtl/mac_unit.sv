`timescale 1ns / 1ps

module mac_unit #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32,
    parameter bit ENABLE_ZERO_GATING = 1'b1
) (
    input  logic                         in_valid,
    input  logic signed [DATA_W-1:0]     act_in,
    input  logic signed [DATA_W-1:0]     wgt_in,
    input  logic signed [ACC_W-1:0]      acc_in,
    output logic signed [ACC_W-1:0]      acc_next,
    output logic                         mac_active
);

    logic signed [ACC_W-1:0] product;

    always_comb begin
        product    = $signed(act_in) * $signed(wgt_in);
        mac_active = in_valid &&
                     !(ENABLE_ZERO_GATING && ((act_in == '0) || (wgt_in == '0)));
        acc_next   = mac_active ? (acc_in + product) : acc_in;
    end

endmodule
