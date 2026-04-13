`timescale 1ns/1ps

module vertex_cover_core #(
    parameter DATA_WIDTH = 64,
    parameter MAX_EDGES  = 512,
    parameter ADDR_WIDTH = 9
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    
    // Interface BRAM (Grafo original)
    output reg  [ADDR_WIDTH-1:0]  addr,
    input  wire [DATA_WIDTH-1:0]  mem_data_in,
    
    // Interface BRAM/Registrador (Máscara de arestas removidas)
    // 0 = Válida, 1 = Removida
    input  wire [MAX_EDGES-1:0]   edge_mask_in,
    output reg  [MAX_EDGES-1:0]   edge_mask_out,
    
    // Controle e status
    output reg                    done,
    output reg  [1:0]             result, // 0=IDLE, 1=SIM, 2=NAO

	 input  wire [31:0]  task_k,    // K que veio da FIFO (Orçamento atual)
    output reg  [31:0]  k_out     // K que será enviado para a próxima tarefa
	 
);

    reg [31:0] selected_vertex;
    reg        vertex_locked;
    reg [ADDR_WIDTH-1:0] i;
    reg [1:0]  state;
    reg        found_any_valid;
	 
	 reg [1:0] scan_step;
	 
    localparam IDLE = 0, SCAN = 1, CHECK_K = 2, FINISH = 3;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
			//$display("Estou RESET!");
            addr          <= 0;
            i             <= 0;
            vertex_locked <= 0;
            done          <= 0;
            result        <= 0;
            edge_mask_out <= 0;
            state         <= IDLE;
				k_out <= task_k;
				
				scan_step <= 0;
        end else begin
            case (state)
                IDLE: begin
							//$display("Estou IDLE!");
                    done          <= 0;
                    i             <= 0;
                    vertex_locked <= 0;
                    found_any_valid <= 0;
                    edge_mask_out <= edge_mask_in;
						  k_out <= task_k;
                    if (start) begin state <= SCAN; end
                end

                SCAN: begin
						  //$display("Estou SCAN!");
						  case(scan_step)
								0: begin
									addr <= i;
									scan_step <= 1;
								end
								1: begin
									scan_step <= 2;
								end
								2: begin

									//$display("(%0d,%0d) | I=%0d", mem_data_in[63:32], mem_data_in[31:0], i);
									//$display("DEBUG: i=%0d | Dado Bruto(Hex)=%h", i, mem_data_in);
									if(!vertex_locked && !edge_mask_out[i] && mem_data_in != 0)begin
										selected_vertex <= mem_data_in[63:32];
										edge_mask_out[i] <= 1;
										//$display("Removido: (%0d,%0d) | I=%0d | V=%0d", mem_data_in[63:32], mem_data_in[31:0], i, selected_vertex);
										vertex_locked <= 1;
										//$display("Achei o V1=%0d!", mem_data_in[63:32]);
									end
									else
									if(i<MAX_EDGES-1 && vertex_locked && !edge_mask_out[i])begin
										if(mem_data_in == 0)begin
											state <= CHECK_K;
										end
										else if(mem_data_in[63:32] == selected_vertex || mem_data_in[31:0] == selected_vertex)begin
											edge_mask_out[i] <= 1;
											//$display("Removido: (%0d,%0d) | I=%0d | V=%0d", mem_data_in[63:32], mem_data_in[31:0], i, selected_vertex);
										end
										else found_any_valid <= 1;
									end
									
									if(i<MAX_EDGES-1)begin
										//$display("Incrementei = %0d | K=%0d", i+1, k_out);
										i <= i + 1;
										scan_step <= 0;
									end
									else state <= CHECK_K;
								end
						  endcase
                end

                CHECK_K: begin
						//$display("Estou CHECK!");
                    // mem_data_in[31:0] contém o K
                    //if (k_out == 1) begin 
						  if (k_out == 1) begin 
                        // Se K-1 == 0, verificar se ainda há arestas
                        if (found_any_valid) result <= 2; // NAO (tem aresta sobrando)
                        else result <= 1;                 // SIM (cobertura completa)
                    end else begin
                        if(!found_any_valid) result <= 1;
								else result <= 0; // Continua
                    end
						  //k_out <= k_out - 1;   // Proximo ramo com K-1
						  k_out <= k_out - 1;
                    state <= FINISH;
                end

                FINISH: begin
						//$display("K=%0d", k_out);
						//$display("Estou FINISH! | Result=%0d", result);
                    //$display("AQUI!");
						  done <= 1;
						  
						  if(!start) state <= IDLE;
                    //state <= IDLE;
                end
            endcase
        end
    end
	 
	 /*always @(posedge clk) begin
    // Se o módulo está trabalhando mas não termina...
		 
			  // Imprime a cada 1000 ciclos para não inundar o log
			  if ($time % 10000 == 0) begin 
					$display("[DEBUG CORE] T=%0t | Estado: %d | Ponteiro: %d", 
								 $time, state, i); // <--- Ajuste 'state' e 'edge_ptr' se os nomes forem diferentes
			  end

	end*/
	
	/*always @(posedge clk) begin
    // Se o módulo está trabalhando mas não termina...
		 
			  // Imprime a cada 1000 ciclos para não inundar o log
			  //if ($time % 10000 == 0) begin 
					$display("[DEBUG CORE ] T=%0t | Estado: %d | Ponteiro: %d | K=%0d", 
								 $time, state, i, k_out); // <--- Ajuste 'state' e 'edge_ptr' se os nomes forem diferentes
			  //end
		 
	end*/
endmodule