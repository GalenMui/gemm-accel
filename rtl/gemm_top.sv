`timescale 1ns / 1ps

module gemm_top #(
    parameter int ARRAY_M = 2,
    parameter int ARRAY_N = 2,
    parameter int TILE_K = 2,
    parameter int DATA_W = 8,
    parameter int ACC_W = 32,
    parameter int DIM_W = 16,
    parameter int A_DEPTH = 4096,
    parameter int B_DEPTH = 4096,
    parameter int C_DEPTH = 4096,
    parameter int A_ADDR_W = $clog2(A_DEPTH),
    parameter int B_ADDR_W = $clog2(B_DEPTH),
    parameter int C_ADDR_W = $clog2(C_DEPTH),
    parameter bit ENABLE_ZERO_GATING = 1'b1
) (
    input  logic                              clk,
    input  logic                              rst,
    input  logic                              start,
    input  logic [DIM_W-1:0]                  cfg_m,
    input  logic [DIM_W-1:0]                  cfg_n,
    input  logic [DIM_W-1:0]                  cfg_k,
    output logic                              busy,
    output logic                              done,
    input  logic                              host_a_en,
    input  logic                              host_a_we,
    input  logic [A_ADDR_W-1:0]               host_a_addr,
    input  logic [DATA_W-1:0]                 host_a_wdata,
    output logic [DATA_W-1:0]                 host_a_rdata,
    input  logic                              host_b_en,
    input  logic                              host_b_we,
    input  logic [B_ADDR_W-1:0]               host_b_addr,
    input  logic [DATA_W-1:0]                 host_b_wdata,
    output logic [DATA_W-1:0]                 host_b_rdata,
    input  logic                              host_c_en,
    input  logic                              host_c_we,
    input  logic [C_ADDR_W-1:0]               host_c_addr,
    input  logic [ACC_W-1:0]                  host_c_wdata,
    output logic [ACC_W-1:0]                  host_c_rdata
);

    localparam int LOAD_A_COUNT = ARRAY_M * TILE_K;
    localparam int LOAD_B_COUNT = TILE_K * ARRAY_N;
    localparam int LOAD_CYCLES  = (LOAD_A_COUNT > LOAD_B_COUNT) ? LOAD_A_COUNT : LOAD_B_COUNT;
    localparam int LOAD_W       = (LOAD_CYCLES > 0) ? $clog2(LOAD_CYCLES + 1) : 1;
    localparam int ROW_IDX_W    = (ARRAY_M > 1) ? $clog2(ARRAY_M) : 1;
    localparam int COL_IDX_W    = (ARRAY_N > 1) ? $clog2(ARRAY_N) : 1;
    localparam int K_IDX_W      = (TILE_K > 1) ? $clog2(TILE_K) : 1;
    localparam int STORE_COUNT  = ARRAY_M * ARRAY_N;
    localparam int STORE_W      = (STORE_COUNT > 1) ? $clog2(STORE_COUNT) : 1;
    localparam int A_TILE_ADDR_W = (LOAD_A_COUNT > 1) ? $clog2(LOAD_A_COUNT) : 1;
    localparam int B_TILE_ADDR_W = (LOAD_B_COUNT > 1) ? $clog2(LOAD_B_COUNT) : 1;
    localparam int C_TILE_ADDR_W = (STORE_COUNT > 1) ? $clog2(STORE_COUNT) : 1;

    logic                           clear_acc;
    logic                           load_phase;
    logic                           load_buf_clear;
    logic                           load_issue;
    logic [LOAD_W-1:0]              load_index;
    logic                           compute_phase;
    logic [K_IDX_W-1:0]             compute_k_idx;
    logic                           capture_phase;
    logic [STORE_W-1:0]             capture_index;
    logic                           store_phase;
    logic [STORE_W-1:0]             store_index;
    logic [DIM_W-1:0]               tile_row_base;
    logic [DIM_W-1:0]               tile_col_base;
    logic [DIM_W-1:0]               k_base;
    logic [DIM_W-1:0]               active_rows;
    logic [DIM_W-1:0]               active_cols;
    logic [DIM_W-1:0]               active_k;

    logic                           accel_a_en;
    logic [A_ADDR_W-1:0]            accel_a_addr;
    logic [DATA_W-1:0]              accel_a_rdata;
    logic                           accel_b_en;
    logic [B_ADDR_W-1:0]            accel_b_addr;
    logic [DATA_W-1:0]              accel_b_rdata;
    logic                           accel_c_en;
    logic                           accel_c_we;
    logic [C_ADDR_W-1:0]            accel_c_addr;
    logic [ACC_W-1:0]               accel_c_wdata;
    logic [ACC_W-1:0]               accel_c_rdata;

    logic signed [DATA_W-1:0]       act_stream [0:ARRAY_M-1];
    logic signed [DATA_W-1:0]       wgt_stream [0:ARRAY_N-1];
    logic signed [ACC_W-1:0]        result_matrix [0:ARRAY_M-1][0:ARRAY_N-1];
    logic [ARRAY_M*TILE_K*DATA_W-1:0] a_tile_flat;
    logic [TILE_K*ARRAY_N*DATA_W-1:0] b_tile_flat;
    logic [ARRAY_M*ARRAY_N*ACC_W-1:0] c_tile_flat;
    logic [ARRAY_M*DATA_W-1:0]      act_stream_flat;
    logic [ARRAY_N*DATA_W-1:0]      wgt_stream_flat;
    logic [ARRAY_M*ARRAY_N*ACC_W-1:0] result_matrix_flat;

    logic [A_TILE_ADDR_W-1:0]       a_tile_write_addr;
    logic [B_TILE_ADDR_W-1:0]       b_tile_write_addr;
    logic                           c_tile_write_en;
    logic [C_TILE_ADDR_W-1:0]       c_tile_write_addr;
    logic [ACC_W-1:0]               c_tile_write_data;

    logic                           a_commit_valid_d;
    logic                           b_commit_valid_d;
    logic [ROW_IDX_W-1:0]           a_row_d;
    logic [K_IDX_W-1:0]             a_k_d;
    logic [K_IDX_W-1:0]             b_k_d;
    logic [COL_IDX_W-1:0]           b_col_d;

    logic                           a_issue_valid;
    logic                           b_issue_valid;
    logic [ROW_IDX_W-1:0]           a_issue_row;
    logic [K_IDX_W-1:0]             a_issue_k;
    logic [K_IDX_W-1:0]             b_issue_k;
    logic [COL_IDX_W-1:0]           b_issue_col;

    logic [ROW_IDX_W-1:0]           store_row_idx;
    logic [COL_IDX_W-1:0]           store_col_idx;
    logic [ROW_IDX_W-1:0]           capture_row_idx;
    logic [COL_IDX_W-1:0]           capture_col_idx;

    integer row;
    integer col;

    controller #(
        .ARRAY_M(ARRAY_M),
        .ARRAY_N(ARRAY_N),
        .TILE_K (TILE_K),
        .DIM_W  (DIM_W)
    ) u_controller (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .cfg_m        (cfg_m),
        .cfg_n        (cfg_n),
        .cfg_k        (cfg_k),
        .busy         (busy),
        .done         (done),
        .clear_acc    (clear_acc),
        .load_phase   (load_phase),
        .load_buf_clear(load_buf_clear),
        .load_issue   (load_issue),
        .load_index   (load_index),
        .compute_phase(compute_phase),
        .compute_k_idx(compute_k_idx),
        .capture_phase(capture_phase),
        .capture_index(capture_index),
        .store_phase  (store_phase),
        .store_index  (store_index),
        .tile_row_base(tile_row_base),
        .tile_col_base(tile_col_base),
        .k_base       (k_base),
        .active_rows  (active_rows),
        .active_cols  (active_cols),
        .active_k     (active_k)
    );

    scratchpad #(
        .DATA_W (DATA_W),
        .DEPTH  (A_DEPTH),
        .ADDR_W (A_ADDR_W),
        .RAM_STYLE("block")
    ) u_a_scratchpad (
        .clk    (clk),
        .a_en   (host_a_en),
        .a_we   (host_a_we),
        .a_addr (host_a_addr),
        .a_wdata(host_a_wdata),
        .a_rdata(host_a_rdata),
        .b_en   (accel_a_en),
        .b_we   (1'b0),
        .b_addr (accel_a_addr),
        .b_wdata({DATA_W{1'b0}}),
        .b_rdata(accel_a_rdata)
    );

    scratchpad #(
        .DATA_W (DATA_W),
        .DEPTH  (B_DEPTH),
        .ADDR_W (B_ADDR_W),
        .RAM_STYLE("block")
    ) u_b_scratchpad (
        .clk    (clk),
        .a_en   (host_b_en),
        .a_we   (host_b_we),
        .a_addr (host_b_addr),
        .a_wdata(host_b_wdata),
        .a_rdata(host_b_rdata),
        .b_en   (accel_b_en),
        .b_we   (1'b0),
        .b_addr (accel_b_addr),
        .b_wdata({DATA_W{1'b0}}),
        .b_rdata(accel_b_rdata)
    );

    scratchpad #(
        .DATA_W (ACC_W),
        .DEPTH  (C_DEPTH),
        .ADDR_W (C_ADDR_W),
        .RAM_STYLE("block")
    ) u_c_scratchpad (
        .clk    (clk),
        .a_en   (host_c_en),
        .a_we   (host_c_we),
        .a_addr (host_c_addr),
        .a_wdata(host_c_wdata),
        .a_rdata(host_c_rdata),
        .b_en   (accel_c_en),
        .b_we   (accel_c_we),
        .b_addr (accel_c_addr),
        .b_wdata(accel_c_wdata),
        .b_rdata(accel_c_rdata)
    );

    tile_buffer #(
        .DATA_W(DATA_W),
        .ROWS  (ARRAY_M),
        .COLS  (TILE_K)
    ) u_a_tile_buffer (
        .clk       (clk),
        .rst       (rst),
        .clear     (load_buf_clear),
        .write_en  (a_commit_valid_d),
        .write_addr(a_tile_write_addr),
        .write_data(accel_a_rdata),
        .data_flat (a_tile_flat)
    );

    tile_buffer #(
        .DATA_W(DATA_W),
        .ROWS  (TILE_K),
        .COLS  (ARRAY_N)
    ) u_b_tile_buffer (
        .clk       (clk),
        .rst       (rst),
        .clear     (load_buf_clear),
        .write_en  (b_commit_valid_d),
        .write_addr(b_tile_write_addr),
        .write_data(accel_b_rdata),
        .data_flat (b_tile_flat)
    );

    tile_buffer #(
        .DATA_W(ACC_W),
        .ROWS  (ARRAY_M),
        .COLS  (ARRAY_N)
    ) u_c_tile_buffer (
        .clk       (clk),
        .rst       (rst),
        .clear     (clear_acc),
        .write_en  (c_tile_write_en),
        .write_addr(c_tile_write_addr),
        .write_data(c_tile_write_data),
        .data_flat (c_tile_flat)
    );

    systolic_array #(
        .ARRAY_M            (ARRAY_M),
        .ARRAY_N            (ARRAY_N),
        .DATA_W             (DATA_W),
        .ACC_W              (ACC_W),
        .ENABLE_ZERO_GATING (ENABLE_ZERO_GATING)
    ) u_systolic_array (
        .clk          (clk),
        .rst          (rst),
        .clear_acc    (clear_acc),
        .stream_valid (compute_phase),
        .act_vec_in_flat   (act_stream_flat),
        .wgt_vec_in_flat   (wgt_stream_flat),
        .result_matrix_flat(result_matrix_flat)
    );

    always_comb begin
        a_issue_valid = 1'b0;
        b_issue_valid = 1'b0;
        a_issue_row   = '0;
        a_issue_k     = '0;
        b_issue_k     = '0;
        b_issue_col   = '0;
        accel_a_en    = 1'b0;
        accel_a_addr  = '0;
        accel_b_en    = 1'b0;
        accel_b_addr  = '0;

        if (load_issue) begin
            if (load_index < LOAD_A_COUNT) begin
                a_issue_row = load_index / TILE_K;
                a_issue_k   = load_index % TILE_K;
                if ((a_issue_row < active_rows) && (a_issue_k < active_k)) begin
                    a_issue_valid = 1'b1;
                    accel_a_en    = 1'b1;
                    accel_a_addr  = ((tile_row_base + a_issue_row) * cfg_k) + (k_base + a_issue_k);
                end
            end

            if (load_index < LOAD_B_COUNT) begin
                b_issue_k   = load_index / ARRAY_N;
                b_issue_col = load_index % ARRAY_N;
                if ((b_issue_k < active_k) && (b_issue_col < active_cols)) begin
                    b_issue_valid = 1'b1;
                    accel_b_en    = 1'b1;
                    accel_b_addr  = ((k_base + b_issue_k) * cfg_n) + (tile_col_base + b_issue_col);
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            a_commit_valid_d <= 1'b0;
            b_commit_valid_d <= 1'b0;
            a_row_d          <= '0;
            a_k_d            <= '0;
            b_k_d            <= '0;
            b_col_d          <= '0;
        end else begin
            a_commit_valid_d <= a_issue_valid;
            b_commit_valid_d <= b_issue_valid;
            a_row_d          <= a_issue_row;
            a_k_d            <= a_issue_k;
            b_k_d            <= b_issue_k;
            b_col_d          <= b_issue_col;
        end
    end

    always_comb begin
        a_tile_write_addr = (a_row_d * TILE_K) + a_k_d;
        b_tile_write_addr = (b_k_d * ARRAY_N) + b_col_d;
    end

    always_comb begin
        for (row = 0; row < ARRAY_M; row++) begin
            act_stream[row] = '0;
        end

        for (col = 0; col < ARRAY_N; col++) begin
            wgt_stream[col] = '0;
        end

        if (compute_phase) begin
            for (row = 0; row < ARRAY_M; row++) begin
                act_stream[row] = $signed(a_tile_flat[(((row * TILE_K) + compute_k_idx) * DATA_W) +: DATA_W]);
            end

            for (col = 0; col < ARRAY_N; col++) begin
                wgt_stream[col] = $signed(b_tile_flat[(((compute_k_idx * ARRAY_N) + col) * DATA_W) +: DATA_W]);
            end
        end
    end

    always_comb begin
        for (row = 0; row < ARRAY_M; row++) begin
            act_stream_flat[(row * DATA_W) +: DATA_W] = act_stream[row];
        end

        for (col = 0; col < ARRAY_N; col++) begin
            wgt_stream_flat[(col * DATA_W) +: DATA_W] = wgt_stream[col];
        end

        for (row = 0; row < ARRAY_M; row++) begin
            for (col = 0; col < ARRAY_N; col++) begin
                result_matrix[row][col] = $signed(result_matrix_flat[((row * ARRAY_N) + col) * ACC_W +: ACC_W]);
            end
        end
    end

    always_comb begin
        c_tile_write_en   = 1'b0;
        c_tile_write_addr = capture_index;
        c_tile_write_data = '0;
        capture_row_idx   = capture_index / ARRAY_N;
        capture_col_idx   = capture_index % ARRAY_N;

        if (capture_phase &&
            (capture_row_idx < active_rows) &&
            (capture_col_idx < active_cols)) begin
            c_tile_write_en   = 1'b1;
            c_tile_write_data = result_matrix[capture_row_idx][capture_col_idx];
        end
    end

    always_comb begin
        accel_c_en    = 1'b0;
        accel_c_we    = 1'b0;
        accel_c_addr  = '0;
        accel_c_wdata = '0;
        store_row_idx = store_index / ARRAY_N;
        store_col_idx = store_index % ARRAY_N;

        if (store_phase &&
            (store_row_idx < active_rows) &&
            (store_col_idx < active_cols)) begin
            accel_c_en    = 1'b1;
            accel_c_we    = 1'b1;
            accel_c_addr  = ((tile_row_base + store_row_idx) * cfg_n) + (tile_col_base + store_col_idx);
            accel_c_wdata = c_tile_flat[(store_index * ACC_W) +: ACC_W];
        end
    end

endmodule
