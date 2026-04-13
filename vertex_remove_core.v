`timescale 1ns/1ps

module vertex_cover_core #(
    parameter MAX_EDGES  = 64
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    
    output reg  [$clog2(MAX_EDGES)-1:0]  addr,
    input  wire [63:0]            mem_data_in,
    
    input  wire [MAX_EDGES-1:0]   edge_mask_in,
    output reg  [MAX_EDGES-1:0]   edge_mask_out,
    
    output reg                    done,
    output reg  [1:0]             result, 
    input  wire [31:0]            task_k,    
    output reg  [31:0]            k_out     
);

    reg [31:0] selected_vertex;
    reg        vertex_locked;
    
    // CORREÇÃO: Removido o "-1". Agora tem 1 bit extra para não dar overflow no MAX_EDGES!
    reg [$clog2(MAX_EDGES):0] i; 
    
    reg [2:0]  step;
    reg        found_any_valid;

    localparam IDLE        = 0,
               FIND_VERTEX = 1,
               REMOVE      = 2,
               CHECK_DONE  = 3,
               FINISH      = 4;

    reg [2:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            i <= 0;
            k_out <= task_k;
            selected_vertex <= 0;
            vertex_locked <= 0;
            done <= 0;
            result <= 0;
            step <= 0;
            addr <= 0;
            edge_mask_out <= 0;
            found_any_valid <= 0;
        end else begin
            case(state)
                IDLE: begin
                    i <= 0;
                    k_out <= task_k;
                    selected_vertex <= 0;
                    vertex_locked <= 0;
                    done <= 0;
                    result <= 0;
                    addr <= 0;
                    found_any_valid <= 0;
                    
                    if (start) begin
                        edge_mask_out <= edge_mask_in;
                        state <= FIND_VERTEX;
                        step <= 0;
                    end
                end

                FIND_VERTEX: begin
                    case(step)
                        0: begin addr <= i[$clog2(MAX_EDGES)-1:0]; step <= 1; end
                        1: begin step <= 2; end 
                        2: begin 
                            if (i < MAX_EDGES) begin
                                if (edge_mask_out[i] == 0 && mem_data_in != 0) begin
                                    selected_vertex <= mem_data_in[63:32];
                                    vertex_locked <= 1;
                                    state <= REMOVE;
                                    i <= 0;
                                    step <= 0;
                                end else begin
                                    i <= i + 1;
                                    step <= 0;
                                end
                            end else begin
                                result <= 1; 
                                state <= FINISH;
                            end
                        end
                    endcase
                end

                REMOVE: begin
                    case(step)
                        0: begin addr <= i[$clog2(MAX_EDGES)-1:0]; step <= 1; end
                        1: begin step <= 2; end
                        2: begin
                            if (i < MAX_EDGES) begin
                                if (edge_mask_out[i] == 0 && mem_data_in != 0) begin
                                    if (mem_data_in[63:32] == selected_vertex || mem_data_in[31:0] == selected_vertex) begin
                                        edge_mask_out[i] <= 1;
                                    end
                                end
                                i <= i + 1; step <= 0;
                            end else begin
                                state <= CHECK_DONE;
                                i <= 0; step <= 0;
                            end
                        end
                    endcase
                end

                CHECK_DONE: begin
                    case(step)
                        0: begin addr <= i[$clog2(MAX_EDGES)-1:0]; step <= 1; end
                        1: begin step <= 2; end
                        2: begin
                            if (i < MAX_EDGES) begin
                                if (edge_mask_out[i] == 0 && mem_data_in != 0) begin
                                    found_any_valid <= 1;
                                    i <= MAX_EDGES; // Agora este registo consegue receber este valor em segurança!
                                    step <= 0;
                                end else begin
                                    i <= i + 1; step <= 0;
                                end
                            end else begin
                                if (found_any_valid) begin
                                    if (k_out <= 1) result <= 2; 
                                    else result <= 0;            
                                end
                                else result <= 1;                 
                                
                                k_out <= k_out - 1;
                                state <= FINISH;
                            end
                        end
                    endcase
                end

                FINISH: begin
                    done <= 1;
                    if(!start) state <= IDLE;
                end
            endcase
        end
    end
endmodule