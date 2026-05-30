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

    logic signed [ACC_W-1:0] acc_next;
    logic                    mac_active;

    mac_unit #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .ENABLE_ZERO_GATING(ENABLE_ZERO_GATING)
    ) u_mac_unit (
        .in_valid  (in_valid),
        .act_in    (act_in),
        .wgt_in    (wgt_in),
        .acc_in    (acc_out),
        .acc_next  (acc_next),
        .mac_active(mac_active)
    );

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
            end else if (in_valid) begin
                acc_out <= acc_next;
            end
        end
    end

endmodule
