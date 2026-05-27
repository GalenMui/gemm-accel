`timescale 1ns / 1ps

module gemm_top_tb;

    localparam int ARRAY_M  = 8;
    localparam int ARRAY_N  = 8;
    localparam int TILE_K   = 8;
    localparam int DATA_W   = 8;
    localparam int ACC_W    = 32;
    localparam int DIM_W    = 16;
    localparam int A_DEPTH  = 512;
    localparam int B_DEPTH  = 512;
    localparam int C_DEPTH  = 512;
    localparam int A_ADDR_W = $clog2(A_DEPTH);
    localparam int B_ADDR_W = $clog2(B_DEPTH);
    localparam int C_ADDR_W = $clog2(C_DEPTH);
    localparam int MAX_M    = 16;
    localparam int MAX_N    = 16;
    localparam int MAX_K    = 16;

    logic                     clk;
    logic                     rst;
    logic                     start;
    logic [DIM_W-1:0]         cfg_m;
    logic [DIM_W-1:0]         cfg_n;
    logic [DIM_W-1:0]         cfg_k;
    logic                     busy;
    logic                     done;

    logic                     host_a_en;
    logic                     host_a_we;
    logic [A_ADDR_W-1:0]      host_a_addr;
    logic [DATA_W-1:0]        host_a_wdata;
    logic [DATA_W-1:0]        host_a_rdata;
    logic                     host_b_en;
    logic                     host_b_we;
    logic [B_ADDR_W-1:0]      host_b_addr;
    logic [DATA_W-1:0]        host_b_wdata;
    logic [DATA_W-1:0]        host_b_rdata;
    logic                     host_c_en;
    logic                     host_c_we;
    logic [C_ADDR_W-1:0]      host_c_addr;
    logic [ACC_W-1:0]         host_c_wdata;
    logic [ACC_W-1:0]         host_c_rdata;

    int signed a_ref     [0:MAX_M-1][0:MAX_K-1];
    int signed b_ref     [0:MAX_K-1][0:MAX_N-1];
    int signed golden_c  [0:MAX_M-1][0:MAX_N-1];

    gemm_top #(
        .ARRAY_M(ARRAY_M),
        .ARRAY_N(ARRAY_N),
        .TILE_K (TILE_K),
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .DIM_W  (DIM_W),
        .A_DEPTH(A_DEPTH),
        .B_DEPTH(B_DEPTH),
        .C_DEPTH(C_DEPTH)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .cfg_m       (cfg_m),
        .cfg_n       (cfg_n),
        .cfg_k       (cfg_k),
        .busy        (busy),
        .done        (done),
        .host_a_en   (host_a_en),
        .host_a_we   (host_a_we),
        .host_a_addr (host_a_addr),
        .host_a_wdata(host_a_wdata),
        .host_a_rdata(host_a_rdata),
        .host_b_en   (host_b_en),
        .host_b_we   (host_b_we),
        .host_b_addr (host_b_addr),
        .host_b_wdata(host_b_wdata),
        .host_b_rdata(host_b_rdata),
        .host_c_en   (host_c_en),
        .host_c_we   (host_c_we),
        .host_c_addr (host_c_addr),
        .host_c_wdata(host_c_wdata),
        .host_c_rdata(host_c_rdata)
    );

    always #5 clk = ~clk;

    function automatic int a_addr(input int row_idx, input int k_idx, input int k_dim);
        a_addr = (row_idx * k_dim) + k_idx;
    endfunction

    function automatic int b_addr(input int k_idx, input int col_idx, input int n_dim);
        b_addr = (k_idx * n_dim) + col_idx;
    endfunction

    function automatic int c_addr(input int row_idx, input int col_idx, input int n_dim);
        c_addr = (row_idx * n_dim) + col_idx;
    endfunction

    function automatic int signed gen_a(input int pattern_id, input int row_idx, input int k_idx);
        case (pattern_id)
            0: begin
                if (((row_idx + k_idx) % 3) == 0) begin
                    gen_a = 0;
                end else begin
                    gen_a = ((row_idx * 2) - k_idx) + 3;
                end
            end
            default: begin
                if ((((row_idx * 2) + k_idx) % 5) == 0) begin
                    gen_a = 0;
                end else begin
                    gen_a = (((row_idx + 1) * (k_idx + 2)) % 9) - 4;
                end
            end
        endcase
    endfunction

    function automatic int signed gen_b(input int pattern_id, input int k_idx, input int col_idx);
        case (pattern_id)
            0: begin
                if (((k_idx + col_idx) % 4) == 0) begin
                    gen_b = 0;
                end else begin
                    gen_b = (k_idx - col_idx) + 2;
                end
            end
            default: begin
                if (((k_idx + (col_idx * 3)) % 7) == 0) begin
                    gen_b = 0;
                end else begin
                    gen_b = (((k_idx + 3) * (col_idx + 1)) % 11) - 5;
                end
            end
        endcase
    endfunction

    task automatic clear_host_ports;
        begin
            host_a_en    <= 1'b0;
            host_a_we    <= 1'b0;
            host_a_addr  <= '0;
            host_a_wdata <= '0;
            host_b_en    <= 1'b0;
            host_b_we    <= 1'b0;
            host_b_addr  <= '0;
            host_b_wdata <= '0;
            host_c_en    <= 1'b0;
            host_c_we    <= 1'b0;
            host_c_addr  <= '0;
            host_c_wdata <= '0;
        end
    endtask

    task automatic write_a_spad(input int addr, input int signed value);
        begin
            @(negedge clk);
            host_a_en    <= 1'b1;
            host_a_we    <= 1'b1;
            host_a_addr  <= addr[A_ADDR_W-1:0];
            host_a_wdata <= value[DATA_W-1:0];
            @(negedge clk);
            host_a_en    <= 1'b0;
            host_a_we    <= 1'b0;
            host_a_addr  <= '0;
            host_a_wdata <= '0;
        end
    endtask

    task automatic write_b_spad(input int addr, input int signed value);
        begin
            @(negedge clk);
            host_b_en    <= 1'b1;
            host_b_we    <= 1'b1;
            host_b_addr  <= addr[B_ADDR_W-1:0];
            host_b_wdata <= value[DATA_W-1:0];
            @(negedge clk);
            host_b_en    <= 1'b0;
            host_b_we    <= 1'b0;
            host_b_addr  <= '0;
            host_b_wdata <= '0;
        end
    endtask

    task automatic read_c_spad(input int addr, output int signed value);
        begin
            @(negedge clk);
            host_c_en   <= 1'b1;
            host_c_we   <= 1'b0;
            host_c_addr <= addr[C_ADDR_W-1:0];
            @(negedge clk);
            value       = $signed(host_c_rdata);
            host_c_en   <= 1'b0;
            host_c_addr <= '0;
        end
    endtask

    task automatic start_gemm(input int m_dim, input int n_dim, input int k_dim);
        begin
            @(negedge clk);
            cfg_m <= m_dim[DIM_W-1:0];
            cfg_n <= n_dim[DIM_W-1:0];
            cfg_k <= k_dim[DIM_W-1:0];
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;
        end
    endtask

    task automatic wait_for_done(input int max_cycles);
        int cycle_count;
        begin
            cycle_count = 0;
            while ((done !== 1'b1) && (cycle_count < max_cycles)) begin
                @(posedge clk);
                cycle_count++;
            end

            if (done !== 1'b1) begin
                $fatal(1, "Timed out waiting for GEMM completion after %0d cycles", max_cycles);
            end

            @(posedge clk);
        end
    endtask

    task automatic prepare_case(input int pattern_id, input int m_dim, input int n_dim, input int k_dim);
        int row_idx;
        int col_idx;
        int k_idx;
        begin
            for (row_idx = 0; row_idx < MAX_M; row_idx++) begin
                for (k_idx = 0; k_idx < MAX_K; k_idx++) begin
                    a_ref[row_idx][k_idx] = 0;
                end
            end

            for (k_idx = 0; k_idx < MAX_K; k_idx++) begin
                for (col_idx = 0; col_idx < MAX_N; col_idx++) begin
                    b_ref[k_idx][col_idx] = 0;
                end
            end

            for (row_idx = 0; row_idx < MAX_M; row_idx++) begin
                for (col_idx = 0; col_idx < MAX_N; col_idx++) begin
                    golden_c[row_idx][col_idx] = 0;
                end
            end

            for (row_idx = 0; row_idx < m_dim; row_idx++) begin
                for (k_idx = 0; k_idx < k_dim; k_idx++) begin
                    a_ref[row_idx][k_idx] = gen_a(pattern_id, row_idx, k_idx);
                    write_a_spad(a_addr(row_idx, k_idx, k_dim), a_ref[row_idx][k_idx]);
                end
            end

            for (k_idx = 0; k_idx < k_dim; k_idx++) begin
                for (col_idx = 0; col_idx < n_dim; col_idx++) begin
                    b_ref[k_idx][col_idx] = gen_b(pattern_id, k_idx, col_idx);
                    write_b_spad(b_addr(k_idx, col_idx, n_dim), b_ref[k_idx][col_idx]);
                end
            end

            for (row_idx = 0; row_idx < m_dim; row_idx++) begin
                for (col_idx = 0; col_idx < n_dim; col_idx++) begin
                    golden_c[row_idx][col_idx] = 0;
                    for (k_idx = 0; k_idx < k_dim; k_idx++) begin
                        golden_c[row_idx][col_idx] += a_ref[row_idx][k_idx] * b_ref[k_idx][col_idx];
                    end
                end
            end
        end
    endtask

    task automatic check_case(input string case_name, input int m_dim, input int n_dim);
        int row_idx;
        int col_idx;
        int signed observed;
        int mismatch_count;
        begin
            mismatch_count = 0;

            for (row_idx = 0; row_idx < m_dim; row_idx++) begin
                for (col_idx = 0; col_idx < n_dim; col_idx++) begin
                    read_c_spad(c_addr(row_idx, col_idx, n_dim), observed);
                    if (observed !== golden_c[row_idx][col_idx]) begin
                        mismatch_count++;
                        $display(
                            "Mismatch %s: C[%0d][%0d] expected=%0d observed=%0d",
                            case_name,
                            row_idx,
                            col_idx,
                            golden_c[row_idx][col_idx],
                            observed
                        );
                    end
                end
            end

            if (mismatch_count != 0) begin
                $fatal(1, "%s failed with %0d mismatches", case_name, mismatch_count);
            end else begin
                $display("PASS: %s", case_name);
            end
        end
    endtask

    task automatic run_case(
        input string case_name,
        input int pattern_id,
        input int m_dim,
        input int n_dim,
        input int k_dim
    );
        begin
            $display("Running %s with M=%0d N=%0d K=%0d", case_name, m_dim, n_dim, k_dim);
            prepare_case(pattern_id, m_dim, n_dim, k_dim);
            start_gemm(m_dim, n_dim, k_dim);
            wait_for_done(5000);
            check_case(case_name, m_dim, n_dim);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        start = 1'b0;
        cfg_m = '0;
        cfg_n = '0;
        cfg_k = '0;
        clear_host_ports();

        repeat (4) @(posedge clk);
        rst = 1'b0;

        run_case("single_tile_sparse_4x4x4", 0, 4, 4, 4);
        run_case("multi_tile_10x9x12",      1, 10, 9, 12);

        $display("All GEMM accelerator tests passed.");
        $finish;
    end

endmodule
