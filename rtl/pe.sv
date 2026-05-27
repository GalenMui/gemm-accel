`timescale 1ns / 1ps

module pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32,
    parameter bit ENABLE_ZERO_GATING = 1'b1
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear_acc,
    input  logic                         in_valid,
    input  logic signed [DATA_W-1:0]     act_in,
    input  logic signed [DATA_W-1:0]     wgt_in,
    output logic                         out_valid,
    output logic signed [DATA_W-1:0]     act_out,
    output logic signed [DATA_W-1:0]     wgt_out,
    output logic signed [ACC_W-1:0]      acc_out
);

    logic skip_mac;

    always_comb begin
        skip_mac = ENABLE_ZERO_GATING && ((act_in == '0) || (wgt_in == '0));
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            act_out   <= '0;
            wgt_out   <= '0;
            out_valid <= 1'b0;
            acc_out   <= '0;
        end else begin
            act_out   <= act_in;
            wgt_out   <= wgt_in;
            out_valid <= in_valid;

            if (clear_acc) begin
                acc_out <= '0;
            end else if (in_valid && !skip_mac) begin
                acc_out <= acc_out + ($signed(act_in) * $signed(wgt_in));
            end
        end
    end

endmodule
