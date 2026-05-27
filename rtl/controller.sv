`timescale 1ns / 1ps

module controller #(
    parameter int ARRAY_M = 8,
    parameter int ARRAY_N = 8,
    parameter int TILE_K = 8,
    parameter int DIM_W = 16
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         start,
    input  logic [DIM_W-1:0]             cfg_m,
    input  logic [DIM_W-1:0]             cfg_n,
    input  logic [DIM_W-1:0]             cfg_k,
    output logic                         busy,
    output logic                         done,
    output logic                         clear_acc,
    output logic                         load_phase,
    output logic                         load_buf_clear,
    output logic                         load_issue,
    output logic [$clog2(((ARRAY_M*TILE_K) > (TILE_K*ARRAY_N) ? (ARRAY_M*TILE_K) : (TILE_K*ARRAY_N)) + 1)-1:0] load_index,
    output logic                         compute_phase,
    output logic [$clog2(TILE_K)-1:0]    compute_k_idx,
    output logic                         store_phase,
    output logic [$clog2(ARRAY_M*ARRAY_N)-1:0] store_index,
    output logic [DIM_W-1:0]             tile_row_base,
    output logic [DIM_W-1:0]             tile_col_base,
    output logic [DIM_W-1:0]             k_base,
    output logic [DIM_W-1:0]             active_rows,
    output logic [DIM_W-1:0]             active_cols,
    output logic [DIM_W-1:0]             active_k
);

    localparam int LOAD_A_COUNT = ARRAY_M * TILE_K;
    localparam int LOAD_B_COUNT = TILE_K * ARRAY_N;
    localparam int LOAD_CYCLES  = (LOAD_A_COUNT > LOAD_B_COUNT) ? LOAD_A_COUNT : LOAD_B_COUNT;
    localparam int DRAIN_CYCLES = ARRAY_M + ARRAY_N - 2;
    localparam int LOAD_W       = $clog2(LOAD_CYCLES + 1);
    localparam int COMPUTE_W    = (TILE_K > 1) ? $clog2(TILE_K) : 1;
    localparam int DRAIN_W      = (DRAIN_CYCLES > 0) ? $clog2(DRAIN_CYCLES + 1) : 1;
    localparam int STORE_W      = $clog2(ARRAY_M * ARRAY_N);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CLEAR,
        ST_LOAD,
        ST_COMPUTE,
        ST_DRAIN,
        ST_STORE,
        ST_DONE
    } state_t;

    state_t state;

    logic [LOAD_W-1:0]    load_count;
    logic [COMPUTE_W-1:0] compute_count;
    logic [DRAIN_W-1:0]   drain_count;
    logic [STORE_W-1:0]   store_count;

    logic [DIM_W-1:0] next_tile_row_base;
    logic [DIM_W-1:0] next_tile_col_base;
    logic [DIM_W-1:0] next_k_base;

    logic more_k_tiles;
    logic more_n_tiles;
    logic more_m_tiles;
    logic cfg_nonzero;

    always_comb begin
        if ((cfg_m - tile_row_base) > ARRAY_M) begin
            active_rows = ARRAY_M;
        end else begin
            active_rows = cfg_m - tile_row_base;
        end

        if ((cfg_n - tile_col_base) > ARRAY_N) begin
            active_cols = ARRAY_N;
        end else begin
            active_cols = cfg_n - tile_col_base;
        end

        if ((cfg_k - k_base) > TILE_K) begin
            active_k = TILE_K;
        end else begin
            active_k = cfg_k - k_base;
        end
    end

    always_comb begin
        cfg_nonzero   = (cfg_m != '0) && (cfg_n != '0) && (cfg_k != '0);
        more_k_tiles  = (k_base + TILE_K) < cfg_k;
        more_n_tiles  = (tile_col_base + ARRAY_N) < cfg_n;
        more_m_tiles  = (tile_row_base + ARRAY_M) < cfg_m;
        next_tile_row_base = tile_row_base;
        next_tile_col_base = tile_col_base;
        next_k_base        = k_base;

        if (more_k_tiles) begin
            next_k_base = k_base + TILE_K;
        end else if (more_n_tiles) begin
            next_k_base        = '0;
            next_tile_col_base = tile_col_base + ARRAY_N;
        end else if (more_m_tiles) begin
            next_k_base        = '0;
            next_tile_col_base = '0;
            next_tile_row_base = tile_row_base + ARRAY_M;
        end else begin
            next_k_base        = '0;
            next_tile_col_base = '0;
            next_tile_row_base = '0;
        end
    end

    assign busy           = (state != ST_IDLE) && (state != ST_DONE);
    assign done           = (state == ST_DONE);
    assign clear_acc      = (state == ST_CLEAR);
    assign load_phase     = (state == ST_LOAD);
    assign load_buf_clear = (state == ST_LOAD) && (load_count == '0);
    assign load_issue     = (state == ST_LOAD) && (load_count < LOAD_CYCLES);
    assign load_index     = load_count;
    assign compute_phase  = (state == ST_COMPUTE);
    assign compute_k_idx  = compute_count;
    assign store_phase    = (state == ST_STORE);
    assign store_index    = store_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= ST_IDLE;
            tile_row_base <= '0;
            tile_col_base <= '0;
            k_base        <= '0;
            load_count    <= '0;
            compute_count <= '0;
            drain_count   <= '0;
            store_count   <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    load_count    <= '0;
                    compute_count <= '0;
                    drain_count   <= '0;
                    store_count   <= '0;
                    if (start && cfg_nonzero) begin
                        tile_row_base <= '0;
                        tile_col_base <= '0;
                        k_base        <= '0;
                        state         <= ST_CLEAR;
                    end
                end

                ST_CLEAR: begin
                    load_count <= '0;
                    state      <= ST_LOAD;
                end

                ST_LOAD: begin
                    if (load_count == LOAD_CYCLES) begin
                        load_count    <= '0;
                        compute_count <= '0;
                        state         <= ST_COMPUTE;
                    end else begin
                        load_count <= load_count + 1'b1;
                    end
                end

                ST_COMPUTE: begin
                    if (compute_count == (TILE_K - 1)) begin
                        compute_count <= '0;
                        if (DRAIN_CYCLES == 0) begin
                            if (more_k_tiles) begin
                                k_base     <= next_k_base;
                                load_count <= '0;
                                state      <= ST_LOAD;
                            end else begin
                                store_count <= '0;
                                state       <= ST_STORE;
                            end
                        end else begin
                            drain_count <= '0;
                            state       <= ST_DRAIN;
                        end
                    end else begin
                        compute_count <= compute_count + 1'b1;
                    end
                end

                ST_DRAIN: begin
                    if (drain_count == (DRAIN_CYCLES - 1)) begin
                        drain_count <= '0;
                        if (more_k_tiles) begin
                            k_base     <= next_k_base;
                            load_count <= '0;
                            state      <= ST_LOAD;
                        end else begin
                            store_count <= '0;
                            state       <= ST_STORE;
                        end
                    end else begin
                        drain_count <= drain_count + 1'b1;
                    end
                end

                ST_STORE: begin
                    if (store_count == (ARRAY_M * ARRAY_N - 1)) begin
                        store_count <= '0;
                        if (more_n_tiles || more_m_tiles) begin
                            tile_row_base <= next_tile_row_base;
                            tile_col_base <= next_tile_col_base;
                            k_base        <= '0;
                            state         <= ST_CLEAR;
                        end else begin
                            state <= ST_DONE;
                        end
                    end else begin
                        store_count <= store_count + 1'b1;
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
