`timescale 1ns / 1ps

`ifndef TILE_M
`define TILE_M 2
`endif

`ifndef TILE_N
`define TILE_N 2
`endif

`ifndef TILE_K
`define TILE_K 2
`endif

module gemm_accel_tb;

    localparam int TILE_M      = `TILE_M;
    localparam int TILE_N      = `TILE_N;
    localparam int TILE_K      = `TILE_K;
    localparam int DATA_WIDTH  = 8;
    localparam int ACC_WIDTH   = 32;
    localparam int DIM_WIDTH   = 16;
    localparam int A_DEPTH     = 4096;
    localparam int B_DEPTH     = 4096;
    localparam int C_DEPTH     = 4096;
    localparam int A_ADDR_WIDTH = $clog2(A_DEPTH);
    localparam int B_ADDR_WIDTH = $clog2(B_DEPTH);
    localparam int C_ADDR_WIDTH = $clog2(C_DEPTH);
    localparam int PEAK_MACS_PER_CYCLE = TILE_M * TILE_N;

    logic                       clk;
    logic                       rst;
    logic                       start;
    logic [DIM_WIDTH-1:0]       cfg_m;
    logic [DIM_WIDTH-1:0]       cfg_n;
    logic [DIM_WIDTH-1:0]       cfg_k;
    logic                       busy;
    logic                       done;

    logic                       host_a_en;
    logic                       host_a_we;
    logic [A_ADDR_WIDTH-1:0]    host_a_addr;
    logic [DATA_WIDTH-1:0]      host_a_wdata;
    logic [DATA_WIDTH-1:0]      host_a_rdata;
    logic                       host_b_en;
    logic                       host_b_we;
    logic [B_ADDR_WIDTH-1:0]    host_b_addr;
    logic [DATA_WIDTH-1:0]      host_b_wdata;
    logic [DATA_WIDTH-1:0]      host_b_rdata;
    logic                       host_c_en;
    logic                       host_c_we;
    logic [C_ADDR_WIDTH-1:0]    host_c_addr;
    logic [ACC_WIDTH-1:0]       host_c_wdata;
    logic [ACC_WIDTH-1:0]       host_c_rdata;

    logic [DATA_WIDTH-1:0]      a_mem [0:A_DEPTH-1];
    logic [DATA_WIDTH-1:0]      b_mem [0:B_DEPTH-1];
    logic [ACC_WIDTH-1:0]       c_expected [0:C_DEPTH-1];

    string vector_root;
    string manifest_path;

    gemm_accel #(
        .TILE_M    (TILE_M),
        .TILE_N    (TILE_N),
        .TILE_K    (TILE_K),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .DIM_WIDTH (DIM_WIDTH),
        .A_DEPTH   (A_DEPTH),
        .B_DEPTH   (B_DEPTH),
        .C_DEPTH   (C_DEPTH)
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

    function automatic int c_addr(input int row_idx, input int col_idx, input int n_dim);
        c_addr = (row_idx * n_dim) + col_idx;
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

    task automatic clear_vector_memories;
        int idx;
        begin
            for (idx = 0; idx < A_DEPTH; idx++) begin
                a_mem[idx] = '0;
            end
            for (idx = 0; idx < B_DEPTH; idx++) begin
                b_mem[idx] = '0;
            end
            for (idx = 0; idx < C_DEPTH; idx++) begin
                c_expected[idx] = '0;
            end
        end
    endtask

    task automatic write_a_spad(input int addr, input logic [DATA_WIDTH-1:0] value);
        begin
            @(negedge clk);
            host_a_en    <= 1'b1;
            host_a_we    <= 1'b1;
            host_a_addr  <= addr[A_ADDR_WIDTH-1:0];
            host_a_wdata <= value;
            @(negedge clk);
            host_a_en    <= 1'b0;
            host_a_we    <= 1'b0;
            host_a_addr  <= '0;
            host_a_wdata <= '0;
        end
    endtask

    task automatic write_b_spad(input int addr, input logic [DATA_WIDTH-1:0] value);
        begin
            @(negedge clk);
            host_b_en    <= 1'b1;
            host_b_we    <= 1'b1;
            host_b_addr  <= addr[B_ADDR_WIDTH-1:0];
            host_b_wdata <= value;
            @(negedge clk);
            host_b_en    <= 1'b0;
            host_b_we    <= 1'b0;
            host_b_addr  <= '0;
            host_b_wdata <= '0;
        end
    endtask

    task automatic write_c_spad(input int addr, input logic [ACC_WIDTH-1:0] value);
        begin
            @(negedge clk);
            host_c_en    <= 1'b1;
            host_c_we    <= 1'b1;
            host_c_addr  <= addr[C_ADDR_WIDTH-1:0];
            host_c_wdata <= value;
            @(negedge clk);
            host_c_en    <= 1'b0;
            host_c_we    <= 1'b0;
            host_c_addr  <= '0;
            host_c_wdata <= '0;
        end
    endtask

    task automatic read_c_spad(input int addr, output logic [ACC_WIDTH-1:0] value);
        begin
            @(negedge clk);
            host_c_en   <= 1'b1;
            host_c_we   <= 1'b0;
            host_c_addr <= addr[C_ADDR_WIDTH-1:0];
            @(negedge clk);
            value       = host_c_rdata;
            host_c_en   <= 1'b0;
            host_c_addr <= '0;
        end
    endtask

    task automatic start_gemm(input int m_dim, input int n_dim, input int k_dim);
        begin
            @(negedge clk);
            cfg_m <= m_dim[DIM_WIDTH-1:0];
            cfg_n <= n_dim[DIM_WIDTH-1:0];
            cfg_k <= k_dim[DIM_WIDTH-1:0];
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;
        end
    endtask

    task automatic wait_for_done(input int max_cycles, output int cycle_count);
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

    task automatic load_case_vectors(
        input string case_name,
        input int m_dim,
        input int n_dim,
        input int k_dim
    );
        string a_path;
        string b_path;
        string c_path;
        int idx;
        int a_count;
        int b_count;
        int c_count;
        begin
            clear_vector_memories();

            a_path = $sformatf("%s/%s/a.mem", vector_root, case_name);
            b_path = $sformatf("%s/%s/b.mem", vector_root, case_name);
            c_path = $sformatf("%s/%s/c.mem", vector_root, case_name);
            a_count = m_dim * k_dim;
            b_count = k_dim * n_dim;
            c_count = m_dim * n_dim;

            $readmemh(a_path, a_mem, 0, a_count - 1);
            $readmemh(b_path, b_mem, 0, b_count - 1);
            $readmemh(c_path, c_expected, 0, c_count - 1);

            for (idx = 0; idx < a_count; idx++) begin
                write_a_spad(idx, a_mem[idx]);
            end
            for (idx = 0; idx < b_count; idx++) begin
                write_b_spad(idx, b_mem[idx]);
            end
            for (idx = 0; idx < c_count; idx++) begin
                write_c_spad(idx, '0);
            end
        end
    endtask

    task automatic check_case(input string case_name, input int m_dim, input int n_dim);
        int row_idx;
        int col_idx;
        int addr;
        int mismatch_count;
        logic [ACC_WIDTH-1:0] observed;
        logic [ACC_WIDTH-1:0] expected;
        begin
            mismatch_count = 0;

            for (row_idx = 0; row_idx < m_dim; row_idx++) begin
                for (col_idx = 0; col_idx < n_dim; col_idx++) begin
                    addr = c_addr(row_idx, col_idx, n_dim);
                    read_c_spad(addr, observed);
                    expected = c_expected[addr];
                    if (observed !== expected) begin
                        mismatch_count++;
                        $display(
                            "Mismatch %s: C[%0d][%0d] expected=%0d observed=%0d expected_hex=%h observed_hex=%h",
                            case_name,
                            row_idx,
                            col_idx,
                            $signed(expected),
                            $signed(observed),
                            expected,
                            observed
                        );
                    end
                end
            end

            if (mismatch_count != 0) begin
                $fatal(1, "%s failed with %0d mismatches", case_name, mismatch_count);
            end else begin
                $display("PASS case=%s", case_name);
            end
        end
    endtask

    task automatic report_perf(
        input string case_name,
        input int m_dim,
        input int n_dim,
        input int k_dim,
        input int cycles
    );
        int mac_ops;
        real macs_per_cycle;
        real utilization_pct;
        begin
            mac_ops = m_dim * n_dim * k_dim;
            macs_per_cycle = $itor(mac_ops) / $itor(cycles);
            utilization_pct = 100.0 * macs_per_cycle / $itor(PEAK_MACS_PER_CYCLE);
            $display(
                "PERF case=%s M=%0d N=%0d K=%0d TILE_M=%0d TILE_N=%0d TILE_K=%0d cycles=%0d mac_ops=%0d macs_per_cycle=%0.3f peak_macs_per_cycle=%0d utilization_pct=%0.2f",
                case_name,
                m_dim,
                n_dim,
                k_dim,
                TILE_M,
                TILE_N,
                TILE_K,
                cycles,
                mac_ops,
                macs_per_cycle,
                PEAK_MACS_PER_CYCLE,
                utilization_pct
            );
        end
    endtask

    task automatic run_case(
        input string case_name,
        input int m_dim,
        input int n_dim,
        input int k_dim
    );
        int cycles;
        begin
            $display("RUN case=%s M=%0d N=%0d K=%0d TILE=%0dx%0dx%0d", case_name, m_dim, n_dim, k_dim, TILE_M, TILE_N, TILE_K);
            load_case_vectors(case_name, m_dim, n_dim, k_dim);
            start_gemm(m_dim, n_dim, k_dim);
            wait_for_done(200000, cycles);
            check_case(case_name, m_dim, n_dim);
            report_perf(case_name, m_dim, n_dim, k_dim, cycles);
        end
    endtask

    initial begin
        int manifest_fd;
        int fields;
        int test_count;
        string case_name;
        int m_dim;
        int n_dim;
        int k_dim;

        clk = 1'b0;
        rst = 1'b1;
        start = 1'b0;
        cfg_m = '0;
        cfg_n = '0;
        cfg_k = '0;
        clear_host_ports();
        clear_vector_memories();

        if (!$value$plusargs("VECTOR_ROOT=%s", vector_root)) begin
            vector_root = "tb/test_vectors/default";
        end
        manifest_path = $sformatf("%s/manifest.txt", vector_root);

        repeat (4) @(posedge clk);
        rst = 1'b0;

        manifest_fd = $fopen(manifest_path, "r");
        if (manifest_fd == 0) begin
            $fatal(1, "Could not open test manifest: %s", manifest_path);
        end

        test_count = 0;
        while (!$feof(manifest_fd)) begin
            fields = $fscanf(manifest_fd, "%s %d %d %d\n", case_name, m_dim, n_dim, k_dim);
            if (fields == 4) begin
                run_case(case_name, m_dim, n_dim, k_dim);
                test_count++;
            end
        end
        $fclose(manifest_fd);

        if (test_count == 0) begin
            $fatal(1, "No GEMM test cases found in %s", manifest_path);
        end

        $display("All %0d GEMM accelerator tests passed.", test_count);
        $finish;
    end

endmodule
