`timescale 1ns / 1ps

module systolic_array #(
    parameter int ARRAY_M = 2,
    parameter int ARRAY_N = 2,
    parameter int DATA_W = 8,
    parameter int ACC_W = 32,
    parameter bit ENABLE_ZERO_GATING = 1'b1
) (
    input  logic                                     clk,
    input  logic                                     rst,
    input  logic                                     clear_acc,
    input  logic                                     stream_valid,
    input  logic [ARRAY_M*DATA_W-1:0]                act_vec_in_flat,
    input  logic [ARRAY_N*DATA_W-1:0]                wgt_vec_in_flat,
    output logic [ARRAY_M*ARRAY_N*ACC_W-1:0]         result_matrix_flat
);

    logic signed [DATA_W-1:0] act_vec_in       [0:ARRAY_M-1];
    logic signed [DATA_W-1:0] wgt_vec_in       [0:ARRAY_N-1];
    logic signed [DATA_W-1:0] act_skew_data   [0:ARRAY_M-1][0:ARRAY_M-1];
    logic                     act_skew_valid  [0:ARRAY_M-1][0:ARRAY_M-1];
    logic signed [DATA_W-1:0] wgt_skew_data   [0:ARRAY_N-1][0:ARRAY_N-1];

    logic signed [DATA_W-1:0] act_bus         [0:ARRAY_M-1][0:ARRAY_N];
    logic                     valid_bus       [0:ARRAY_M-1][0:ARRAY_N];
    logic signed [DATA_W-1:0] wgt_bus         [0:ARRAY_M][0:ARRAY_N-1];
    logic signed [ACC_W-1:0]  acc_matrix      [0:ARRAY_M-1][0:ARRAY_N-1];

    genvar row_idx;
    genvar col_idx;
    genvar pe_row;
    genvar pe_col;
    genvar flat_row;
    genvar flat_col;

    generate
        for (flat_row = 0; flat_row < ARRAY_M; flat_row++) begin : gen_unpack_act
            assign act_vec_in[flat_row] = $signed(act_vec_in_flat[(flat_row * DATA_W) +: DATA_W]);
        end

        for (flat_col = 0; flat_col < ARRAY_N; flat_col++) begin : gen_unpack_wgt
            assign wgt_vec_in[flat_col] = $signed(wgt_vec_in_flat[(flat_col * DATA_W) +: DATA_W]);
        end

        for (row_idx = 0; row_idx < ARRAY_M; row_idx++) begin : gen_act_edge
            assign act_bus[row_idx][0]   = act_skew_data[row_idx][row_idx];
            assign valid_bus[row_idx][0] = act_skew_valid[row_idx][row_idx];
        end

        for (col_idx = 0; col_idx < ARRAY_N; col_idx++) begin : gen_wgt_edge
            assign wgt_bus[0][col_idx] = wgt_skew_data[col_idx][col_idx];
        end

        for (pe_row = 0; pe_row < ARRAY_M; pe_row++) begin : gen_pe_rows
            for (pe_col = 0; pe_col < ARRAY_N; pe_col++) begin : gen_pe_cols
                pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W),
                    .ENABLE_ZERO_GATING(ENABLE_ZERO_GATING)
                ) u_pe (
                    .clk      (clk),
                    .rst      (rst),
                    .clear_acc(clear_acc),
                    .in_valid (valid_bus[pe_row][pe_col]),
                    .act_in   (act_bus[pe_row][pe_col]),
                    .wgt_in   (wgt_bus[pe_row][pe_col]),
                    .out_valid(valid_bus[pe_row][pe_col + 1]),
                    .act_out  (act_bus[pe_row][pe_col + 1]),
                    .wgt_out  (wgt_bus[pe_row + 1][pe_col]),
                    .acc_out  (acc_matrix[pe_row][pe_col])
                );

                assign result_matrix_flat[((pe_row * ARRAY_N) + pe_col) * ACC_W +: ACC_W] = acc_matrix[pe_row][pe_col];
            end
        end
    endgenerate

    integer row;
    integer stage;
    integer col;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (row = 0; row < ARRAY_M; row++) begin
                for (stage = 0; stage < ARRAY_M; stage++) begin
                    act_skew_data[row][stage]  <= '0;
                    act_skew_valid[row][stage] <= 1'b0;
                end
            end

            for (col = 0; col < ARRAY_N; col++) begin
                for (stage = 0; stage < ARRAY_N; stage++) begin
                    wgt_skew_data[col][stage] <= '0;
                end
            end
        end else begin
            for (row = 0; row < ARRAY_M; row++) begin
                act_skew_data[row][0]  <= act_vec_in[row];
                act_skew_valid[row][0] <= stream_valid;
                for (stage = 1; stage < ARRAY_M; stage++) begin
                    act_skew_data[row][stage]  <= act_skew_data[row][stage - 1];
                    act_skew_valid[row][stage] <= act_skew_valid[row][stage - 1];
                end
            end

            for (col = 0; col < ARRAY_N; col++) begin
                wgt_skew_data[col][0] <= wgt_vec_in[col];
                for (stage = 1; stage < ARRAY_N; stage++) begin
                    wgt_skew_data[col][stage] <= wgt_skew_data[col][stage - 1];
                end
            end
        end
    end

endmodule
