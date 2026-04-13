`timescale 1ns/1ps

module worker_wrapper # (
    parameter MAX_EDGES = 64
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          start,
    input  wire          solution_found_global, 

    input  wire [MAX_EDGES-1:0]  task_mask,
    input  wire [31:0]           task_k,

    output reg                   done,           
    output reg                   push_core,      
    output reg                   push_neighbor,  
    output reg                   solution_found,
    
    output reg  [MAX_EDGES-1:0]  res_mask_core,
    output reg  [MAX_EDGES-1:0]  res_mask_neighbor,
    output reg  [31:0]           res_k_core,
    output reg  [31:0]           res_k_neighbor,
    
    output reg  [MAX_EDGES-1:0]  res_mask_sol,
    output reg  [31:0]           res_k_sol
);

    // ======================================================================
    // ATRIBUTO MÁGICO DO QUARTUS: Força a usar blocos de memória (BRAM) reais
    // ======================================================================
    (* romstyle = "block" *) reg [63:0] rom [0:MAX_EDGES-1]; 

    initial begin
        $readmemh("grafo.hex", rom);
    end

    wire [$clog2(MAX_EDGES)-1:0]  addr_core, addr_neighbor;
    
    reg [63:0] mem_data_core;
    reg [63:0] mem_data_neighbor;

    // Leitura 100% síncrona
    always @(posedge clk) begin
        mem_data_core     <= rom[addr_core];
        mem_data_neighbor <= rom[addr_neighbor];
    end

    wire done_c, done_n;
    wire [1:0] result_c, result_n;
    wire [31:0] w_k_core, w_k_neighbor;
    wire [MAX_EDGES-1:0] w_mask_core, w_mask_neighbor;

    reg core_busy, neigh_busy, task_active;

    vertex_cover_core #(.MAX_EDGES(MAX_EDGES)) u_core (
        .clk(clk), .rst(rst), .start(start),
        .addr(addr_core), .mem_data_in(mem_data_core),
        .task_k(task_k), .edge_mask_in(task_mask),
        .edge_mask_out(w_mask_core), .done(done_c),
        .result(result_c), .k_out(w_k_core)
    );

    vertex_remove_neighbor #(.MAX_EDGES(MAX_EDGES)) u_neighbor (
        .clk(clk), .rst(rst), .start(start),
        .addr(addr_neighbor), .mem_data_in(mem_data_neighbor),
        .task_k(task_k), .edge_mask_in(task_mask),
        .edge_mask_out(w_mask_neighbor), .done(done_n),
        .result(result_n), .k_out(w_k_neighbor)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0; push_core <= 0; push_neighbor <= 0;
            solution_found <= 0; core_busy <= 0; neigh_busy <= 0;
            task_active <= 0;
        end else if (solution_found_global) begin
            done <= 0; push_core <= 0; push_neighbor <= 0;
            solution_found <= 0; core_busy <= 0; neigh_busy <= 0;
            task_active <= 0;
        end else begin
            if (start) begin
                core_busy <= 1'b1; neigh_busy <= 1'b1;
                task_active <= 1'b1;
                done <= 1'b0; solution_found <= 1'b0;
                push_core <= 1'b0; push_neighbor <= 1'b0;
            end else if (task_active) begin
                if (core_busy && done_c) begin
                    core_busy <= 1'b0;
                    res_k_core <= w_k_core;
                    res_mask_core <= w_mask_core;
                    if (result_c == 2'd1) begin 
                        solution_found <= 1'b1; res_mask_sol <= w_mask_core; res_k_sol <= w_k_core;       
                    end
                    else if (result_c == 2'd0) push_core <= 1'b1; 
                end

                if (neigh_busy && done_n) begin
                    neigh_busy <= 1'b0;
                    res_k_neighbor <= w_k_neighbor;
                    res_mask_neighbor <= w_mask_neighbor;
                    if (result_n == 2'd1) begin
                        solution_found <= 1'b1; res_mask_sol <= w_mask_neighbor; res_k_sol <= w_k_neighbor;       
                    end
                    else if (result_n == 2'd0) push_neighbor <= 1'b1;
                end

                if (solution_found || (!core_busy && !neigh_busy)) begin
                    done <= 1'b1; task_active <= 1'b0;
                end
            end else begin
                done <= 1'b0;
            end
        end
    end
endmodule