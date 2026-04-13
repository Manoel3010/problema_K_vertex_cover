`timescale 1ns/1ps

module top_level # (
    parameter MAX_EDGES = 512,
    parameter NUM_WORKERS = 10
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          start_global,
    input  wire [31:0]   k_input,      
    output reg  [511:0]  best_mask,    
    output reg           all_finished
);

    reg  [543:0] fifo_data [0:63];  
    reg  [5:0]   wr_ptr, rd_ptr;
    reg  [6:0]   fifo_count; 
    reg          has_started, found_solution;
    reg  [31:0]  final_k;

    reg  [NUM_WORKERS-1:0] worker_start;
    wire [NUM_WORKERS-1:0] worker_done, push_c, push_n, sol_found;
    
    // Fios dos ramos separados
    wire [511:0] res_mask_c [0:NUM_WORKERS-1], res_mask_n [0:NUM_WORKERS-1];
    wire [31:0]  res_k_c [0:NUM_WORKERS-1], res_k_n [0:NUM_WORKERS-1];
    
    // NOVOS FIOS: Transportam a máscara e o K exatos de quem encontrou a solução final
    wire [511:0] res_mask_sol [0:NUM_WORKERS-1];
    wire [31:0]  res_k_sol [0:NUM_WORKERS-1];

    reg  [NUM_WORKERS-1:0] worker_busy;
    reg  [31:0]  task_k [0:NUM_WORKERS-1];
    reg  [511:0] task_mask [0:NUM_WORKERS-1];

    reg [5:0] stop_counter;

    genvar g;
    generate
        for (g = 0; g < NUM_WORKERS; g = g + 1) begin : workers
            worker_wrapper u_worker (
                .clk(clk), 
                .rst(rst), 
                .start(worker_start[g]),
                .solution_found_global(found_solution), 
                
                .task_mask(task_mask[g]), 
                .task_k(task_k[g]),
                
                .res_mask_core(res_mask_c[g]), 
                .res_mask_neighbor(res_mask_n[g]),
                .res_k_core(res_k_c[g]), 
                .res_k_neighbor(res_k_n[g]),
                
                // Ligações das portas da solução
                .res_mask_sol(res_mask_sol[g]),
                .res_k_sol(res_k_sol[g]),
                
                .done(worker_done[g]), 
                .push_core(push_c[g]),
                .push_neighbor(push_n[g]), 
                .solution_found(sol_found[g])
            );
        end
    endgenerate

    integer i;
    reg [5:0] v_wr_ptr;
    reg [6:0] v_added, v_consumed;
    reg [5:0] v_rd_ptr;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0; rd_ptr <= 0; fifo_count <= 0;
            has_started <= 0; found_solution <= 0;
            all_finished <= 0; best_mask <= 0; final_k <= 0;
            worker_busy <= 0; worker_start <= 0; stop_counter <= 0;
            for (i = 0; i < NUM_WORKERS; i = i + 1) begin
                task_k[i] <= 0; task_mask[i] <= 0;
            end
        end else begin
            if (start_global && !has_started) begin
                $display("T=%0t | [TOP] INICIANDO BUSCA GLOBAL | K Inicial = %0d", $time, k_input);
                fifo_data[0] <= {k_input, 512'd0}; 
                wr_ptr <= 1; rd_ptr <= 0; fifo_count <= 1;
                has_started <= 1; found_solution <= 0; all_finished <= 0;
            end else if (has_started && !all_finished) begin
                v_wr_ptr = wr_ptr; v_added = 0; v_consumed = 0; v_rd_ptr = rd_ptr;

                // --- RECOLHER RESULTADOS ---
                for (i = 0; i < NUM_WORKERS; i = i + 1) begin
                    if (worker_busy[i] && worker_done[i]) begin
                        worker_busy[i] <= 1'b0;
                        if (sol_found[i]) begin
                            found_solution <= 1'b1;
                            
                            // AGORA ELE LÊ DA FONTE CORRETA (o vencedor)
                            best_mask <= res_mask_sol[i]; 
                            final_k <= res_k_sol[i];
                            
                            $display("T=%0t | [TOP] *** WORKER %0d ENCONTROU A SOLUCAO! ***", $time, i);
                        end else begin
                            $display("T=%0t | [TOP] Worker %0d concluiu avaliacao do vertice.", $time, i);
                            if (push_c[i]) begin
                                fifo_data[v_wr_ptr] <= {res_k_c[i], res_mask_c[i]};
                                v_wr_ptr = (v_wr_ptr + 1) % 64; v_added = v_added + 1;
                                $display("        -> Ramo CORE gerado com sucesso (Novo K=%0d).", res_k_c[i]);
                            end else $display("        -> Ramo CORE DESATIVADO (Podado / Sem Solucao).");

                            if (push_n[i]) begin
                                fifo_data[v_wr_ptr] <= {res_k_n[i], res_mask_n[i]};
                                v_wr_ptr = (v_wr_ptr + 1) % 64; v_added = v_added + 1;
                                $display("        -> Ramo NEIGHBOR gerado com sucesso (Novo K=%0d).", res_k_n[i]);
                            end else $display("        -> Ramo NEIGHBOR DESATIVADO (Podado / Sem Solucao).");
                            
                            // Para manter o log útil em caso de falha, guarda a última máscara do Core tentada
                            best_mask <= res_mask_c[i];
                        end
                    end
                end

                // --- DISTRIBUIR TAREFAS ---
                for (i = 0; i < NUM_WORKERS; i = i + 1) begin
                    // Lê apenas o que já estava na FIFO no início do ciclo (evita o K=x)
                    if (!worker_busy[i] && (fifo_count - v_consumed > 0) && !found_solution) begin
                        task_k[i] <= fifo_data[v_rd_ptr][543:512];
                        task_mask[i] <= fifo_data[v_rd_ptr][511:0];
                        worker_busy[i] <= 1'b1; 
                        worker_start[i] <= 1'b1;
                        $display("T=%0t | [TOP] Distribuindo tarefa para Worker %0d (K_recebido=%0d)", $time, i, fifo_data[v_rd_ptr][543:512]);
                        v_rd_ptr = (v_rd_ptr + 1) % 64; 
                        v_consumed = v_consumed + 1;
                    end else begin
                        worker_start[i] <= 1'b0;
                    end
                end
                
                wr_ptr <= v_wr_ptr;
                rd_ptr <= v_rd_ptr;
                fifo_count <= (fifo_count + v_added) - v_consumed;

                // --- FINALIZAÇÃO ---
                if (found_solution) begin
                    all_finished <= 1'b1; has_started <= 1'b0;
                    $display("==================================================");
                    $display("STATUS: SUCESSO! Solucao encontrada!");
                    $display("K restante no momento da solucao: %0d", final_k);
                    $display("==================================================");
                end else if (fifo_count == 0 && worker_busy == 0 && !start_global) begin
                    if (stop_counter < 40) stop_counter <= stop_counter + 1;
                    else begin
                        all_finished <= 1'b1; has_started <= 1'b0;
                        $display("==================================================");
                        $display("STATUS: FALHA! Busca exaurida sem encontrar solucao.");
                        $display("==================================================");
                    end
                end
            end
        end
    end
endmodule