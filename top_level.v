`timescale 1ns/1ps

module top_level # (
    parameter MAX_EDGES = 64,      // Quantidade máxima de arestas
    parameter NUM_WORKERS = 2,     // Número de workers paralelos
    parameter FIFO_DEPTH = 16      // Profundidade da FIFO (Pode mudar para 32, 64, 128...)
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          start_global,
    

    input  wire [4:0]    sw_k,          // Chaves para inserir o K (0 a 31)
    output reg           led_green_yes, // Acende se encontrou solução (SIM)
    output reg           led_red_no,    // Acende se esgotou e não achou (NÃO)
    output wire [6:0]    hex0,          // Display de 7 seg (Unidades)
    output wire [6:0]    hex1,          // Display de 7 seg (Dezenas)
    
    output reg  [MAX_EDGES-1:0]  best_mask,
    output reg           all_finished
);

    // LÓGICA DO DISPLAY DE 7 SEGMENTOS
	 wire [4:0] display_value;
    // Se achou a solução (luz verde acesa), mostra o K final. Senão, mostra o K das chaves.
    assign display_value = (led_green_yes) ? final_k[4:0] : sw_k;

    decodificador_7seg display_unidade (
        .bin(display_value % 10),
        .seg(hex0)
    );
    
    decodificador_7seg display_dezena (
        .bin(display_value / 10),
        .seg(hex1)
    );

    // FIFO AUTOMÁTICA
    reg  [MAX_EDGES+31:0]         fifo_data [0:FIFO_DEPTH-1];
    reg  [$clog2(FIFO_DEPTH)-1:0] wr_ptr, rd_ptr;   // Ponteiros calculam os bits necessários
    reg  [$clog2(FIFO_DEPTH):0]   fifo_count;       // Contador precisa de 1 bit a mais para o cheio absoluto
    
    reg          has_started, found_solution;
    reg  [31:0]  final_k;

    reg  [NUM_WORKERS-1:0] worker_start;
    wire [NUM_WORKERS-1:0] worker_done, push_c, push_n, sol_found;
    wire [MAX_EDGES-1:0] res_mask_c [0:NUM_WORKERS-1], res_mask_n [0:NUM_WORKERS-1];
    wire [31:0] res_k_c [0:NUM_WORKERS-1], res_k_n [0:NUM_WORKERS-1];
    wire [MAX_EDGES-1:0] res_mask_sol [0:NUM_WORKERS-1];
    wire [31:0] res_k_sol [0:NUM_WORKERS-1];
    reg  [NUM_WORKERS-1:0] worker_busy;
    reg  [31:0] task_k [0:NUM_WORKERS-1];
    reg  [MAX_EDGES-1:0] task_mask [0:NUM_WORKERS-1];

    reg [5:0] stop_counter;

    genvar g;
    generate
        for (g = 0; g < NUM_WORKERS; g = g + 1) begin : workers
            worker_wrapper #(.MAX_EDGES(MAX_EDGES)) u_worker (
                .clk(clk), .rst(rst), .start(worker_start[g]),
                .solution_found_global(found_solution), 
                .task_mask(task_mask[g]), .task_k(task_k[g]),
                .res_mask_core(res_mask_c[g]), .res_mask_neighbor(res_mask_n[g]),
                .res_k_core(res_k_c[g]), .res_k_neighbor(res_k_n[g]),
                .res_mask_sol(res_mask_sol[g]), .res_k_sol(res_k_sol[g]),
                .done(worker_done[g]), .push_core(push_c[g]),
                .push_neighbor(push_n[g]), .solution_found(sol_found[g])
            );
        end
    endgenerate

    integer i;
    // Variáveis combinacionais da FIFO também ajustadas
    reg [$clog2(FIFO_DEPTH)-1:0] v_wr_ptr; 
    reg [$clog2(FIFO_DEPTH):0]   v_added, v_consumed;
    reg [$clog2(FIFO_DEPTH)-1:0] v_rd_ptr;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0; rd_ptr <= 0; fifo_count <= 0;
            has_started <= 0; found_solution <= 0;
            all_finished <= 0; best_mask <= 0;
            final_k <= 0;
            worker_busy <= 0; worker_start <= 0; stop_counter <= 0;
            
            // Resetando os LEDs
            led_green_yes <= 0;
            led_red_no <= 0;

            for (i = 0; i < NUM_WORKERS; i = i + 1) begin
                task_k[i] <= 0; task_mask[i] <= 0;
            end
        end else begin
            if (start_global && !has_started) begin
                // Em vez de K_INICIAL, insere o valor lido das chaves sw_k estendido para 32 bits
                fifo_data[0] <= { {27'b0, sw_k}, {MAX_EDGES{1'b0}}};
                wr_ptr <= 1; rd_ptr <= 0; fifo_count <= 1;
                has_started <= 1; found_solution <= 0; all_finished <= 0;
                
                //Garante que os LEDs estão apagados ao iniciar uma nova busca
                led_green_yes <= 0;
                led_red_no <= 0;
                stop_counter <= 0;
            end else if (has_started && !all_finished) begin
                v_wr_ptr = wr_ptr;
                v_added = 0; v_consumed = 0; v_rd_ptr = rd_ptr;

                for (i = 0; i < NUM_WORKERS; i = i + 1) begin
                    if (worker_busy[i] && worker_done[i]) begin
                        worker_busy[i] <= 1'b0;
                        if (sol_found[i]) begin
                            found_solution <= 1'b1;
                            best_mask <= res_mask_sol[i]; 
                            final_k <= res_k_sol[i];
                        end else begin
                            if (push_c[i]) begin
                                fifo_data[v_wr_ptr] <= {res_k_c[i], res_mask_c[i]};
                                v_wr_ptr = (v_wr_ptr + 1) % FIFO_DEPTH; // Automático
                                v_added = v_added + 1;
                            end
                            if (push_n[i]) begin
                                fifo_data[v_wr_ptr] <= {res_k_n[i], res_mask_n[i]};
                                v_wr_ptr = (v_wr_ptr + 1) % FIFO_DEPTH; // Automático
                                v_added = v_added + 1;
                            end
                            best_mask <= res_mask_c[i];
                        end
                    end
                end

                for (i = 0; i < NUM_WORKERS; i = i + 1) begin
                    if (!worker_busy[i] && (fifo_count - v_consumed > 0) && !found_solution) begin
                        task_k[i] <= fifo_data[v_rd_ptr][MAX_EDGES+31 : MAX_EDGES];
                        task_mask[i] <= fifo_data[v_rd_ptr][MAX_EDGES-1 : 0]; 
                        
                        worker_busy[i] <= 1'b1; worker_start[i] <= 1'b1;
                        v_rd_ptr = (v_rd_ptr + 1) % FIFO_DEPTH; // Automático
                        v_consumed = v_consumed + 1;
                    end else begin
                        worker_start[i] <= 1'b0;
                    end
                end
                
                wr_ptr <= v_wr_ptr; rd_ptr <= v_rd_ptr;
                fifo_count <= (fifo_count + v_added) - v_consumed;

                //Lógica de parada e acendimento dos LEDs Verde e Vermelho
                if (found_solution) begin
                    all_finished <= 1'b1; 
                    has_started <= 1'b0;
                    led_green_yes <= 1'b1; // Instância YES! Acende LED Verde
                end else if (fifo_count == 0 && worker_busy == 0 && !start_global) begin
                    if (stop_counter < 40) stop_counter <= stop_counter + 1;
                    else begin
                        all_finished <= 1'b1; 
                        has_started <= 1'b0;
                        led_red_no <= 1'b1;    // Instância no, Acende LED Vermelho
                    end
                end
            end
        end
    end
endmodule

//  Módulo Decodificador Binário para 7 Segmentos
module decodificador_7seg(
    input  wire [3:0] bin,
    output reg  [6:0] seg
);
    // Na placa DE1, os displays são Anodo Comum (0 acende o segmento, 1 apaga)
    always @(*) begin
        case(bin)
            4'd0: seg = 7'b1000000; 
            4'd1: seg = 7'b1111001; 
            4'd2: seg = 7'b0100100; 
            4'd3: seg = 7'b0110000; 
            4'd4: seg = 7'b0011001; 
            4'd5: seg = 7'b0010010; 
            4'd6: seg = 7'b0000010; 
            4'd7: seg = 7'b1111000; 
            4'd8: seg = 7'b0000000; 
            4'd9: seg = 7'b0010000; 
            default: seg = 7'b1111111; // Apagado
        endcase
    end
endmodule
