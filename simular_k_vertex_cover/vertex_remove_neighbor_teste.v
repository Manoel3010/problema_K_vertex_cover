`timescale 1ns/1ps

module vertex_remove_neighbor #
(
    parameter MAX_EDGES = 512
)
(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    // Interface BRAM
    output reg  [8:0]  addr,
    input  wire [63:0] mem_data_in,

    // Interface de Máscara
    input  wire [511:0] edge_mask_in,
    output reg  [511:0] edge_mask_out,

    output reg         done,
    output reg  [1:0]  result, 
     
    input  wire [31:0]  task_k,    // K que veio da FIFO
    output reg  [31:0]  k_out      // K que será enviado
);

    reg [31:0] i;
    reg [31:0] v1;
    reg [31:0] neighbor;
    reg [1:0]  step; 
     
    localparam IDLE        = 0,
               SELECT_V1   = 1,
               FIND_NEIGH  = 2,
               REMOVE_NEI  = 3,
               CHECK_DONE  = 4,
               CANCEL      = 5,
               FINISH      = 6;

    reg [3:0] state = IDLE;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            i <= 0;
            k_out <= task_k;
            v1 <= 0;
            done <= 0;
            result <= 0;
            step <= 0;
            addr <= 0;
            edge_mask_out <= 0;
        end else begin
            case(state)
                IDLE: begin
                    i <= 0;
                    addr <= 0;
                    k_out <= task_k;
                    done <= 0;
                    result <= 0;
                    v1 <= 0;
                    if (start) begin
                        edge_mask_out <= edge_mask_in;
                        state <= SELECT_V1;
                        step <= 0;
                    end
                end

                SELECT_V1: begin
                    case(step)
                        0: begin addr <= i; step <= 1; end
                        1: begin step <= 2; end
                        2: begin 
                            // Corrigido para MAX_EDGES (garante ler a última posição)
                            if (i < MAX_EDGES) begin
                                if (edge_mask_out[i] == 0 && mem_data_in != 0) begin
                                    v1 <= mem_data_in[63:32]; 
                                    state <= FIND_NEIGH; 
                                    i <= 0; step <= 0;
                                end else begin
                                    i <= i + 1; step <= 0;
                                end
                            end else begin
                                // Se varreu o grafo todo e não achou nada, o grafo está limpo
                                result <= 1;
                                state <= FINISH;
                            end
                        end
                    endcase
                end

                FIND_NEIGH: begin
                    case(step)
                        0: begin addr <= i; step <= 1; end
                        1: step <= 2;
                        2: begin
                            if (i < MAX_EDGES) begin
                                if (edge_mask_out[i] == 0 && mem_data_in != 0) begin
                                    if (mem_data_in[63:32] == v1) begin
                                        neighbor <= mem_data_in[31:0];
                                        state <= REMOVE_NEI; i <= 0; step <= 0;
                                    end else if (mem_data_in[31:0] == v1) begin
                                        neighbor <= mem_data_in[63:32];
                                        state <= REMOVE_NEI; i <= 0; step <= 0;
                                    end else begin
                                        i <= i + 1; step <= 0;
                                    end
                                end else begin
                                    i <= i + 1; step <= 0;
                                end
                            end else begin
                                // Acabaram-se os vizinhos deste vértice! 
                                // O ramo é consistente, agora verifica se o grafo ficou vazio.
                                state <= CHECK_DONE;
                                i <= 0; step <= 0;
                            end
                        end
                    endcase
                end

                REMOVE_NEI: begin
                    case(step)
                        0: begin addr <= i; step <= 1; end
                        1: step <= 2;
                        2: begin
                            if (i < MAX_EDGES) begin
                                if (edge_mask_out[i] == 0 && mem_data_in != 0) begin
                                    if (mem_data_in[63:32] == neighbor || mem_data_in[31:0] == neighbor) begin
                                        edge_mask_out[i] <= 1;
                                    end
                                end
                                i <= i + 1; step <= 0;
                            end else begin
                                // Terminou de remover TODAS as arestas deste vizinho
                                if (k_out == 0) begin
                                    // Se precisava remover o vizinho mas K já era zero: FALHA
                                    state <= CANCEL;
                                end else begin
                                    // Remove do orçamento e procura o próximo vizinho
                                    k_out <= k_out - 1;
                                    state <= FIND_NEIGH; 
                                    i <= 0; step <= 0;
                                end
                            end
                        end
                    endcase
                end

                CHECK_DONE: begin
                    case(step)
                        0: begin addr <= i; step <= 1; end
                        1: step <= 2;
                        2: begin
                            if (i < MAX_EDGES) begin
                                if (edge_mask_out[i] == 0 && mem_data_in != 0) begin
                                    // Encontrou aresta sobrando!
                                    if (k_out == 0) begin
                                        state <= CANCEL; // Sem orçamento para prosseguir (Poda)
                                    end else begin
                                        result <= 0;     // Com orçamento, manda para o Top Level continuar
                                        state <= FINISH;
                                    end
                                end else begin
                                    i <= i + 1; step <= 0;
                                end
                            end else begin
                                // Nenhuma aresta sobrando: SUCESSO!
                                result <= 1;
                                state <= FINISH;
                            end
                        end
                    endcase
                end

                CANCEL: begin
                    result <= 2;
                    state <= FINISH;
                end

                FINISH: begin
                    done <= 1;
                    if (!start) state <= IDLE;
                end
            endcase
        end
    end
endmodule