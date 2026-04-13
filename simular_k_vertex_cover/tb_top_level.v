`timescale 1ns/1ps

module top_level_tb;
    reg clk, rst, start_global;
    reg [31:0] k_input;
    wire all_finished;
    
    integer timeout_counter;

    top_level #(.NUM_WORKERS(10)) uut (
        .clk(clk), .rst(rst),
        .start_global(start_global),
        .k_input(k_input),
        .all_finished(all_finished)
    );

    always #5 clk = ~clk;

    // =========================================================
    // SOLUÇÃO: Usar 'genvar' para aceder a instâncias geradas!
    // =========================================================
    genvar gw;
    generate
        for (gw = 0; gw < 10; gw = gw + 1) begin : init_rom
            initial begin
                // Zera todas as posições primeiro (o índice do array pode ser variável normal)
                for (integer i = 0; i < 512; i = i + 1) begin
                    uut.workers[gw].u_worker.rom[i] = 64'd0;
                end
                
                // Insere o grafo idêntico em cada worker				 
					 /*uut.workers[gw].u_worker.rom[0] = {32'd1, 32'd2}; 
                uut.workers[gw].u_worker.rom[1] = {32'd1, 32'd3};
                uut.workers[gw].u_worker.rom[2] = {32'd2, 32'd4}; 
                uut.workers[gw].u_worker.rom[3] = {32'd3, 32'd5};
                uut.workers[gw].u_worker.rom[4] = {32'd4, 32'd6}; 
                uut.workers[gw].u_worker.rom[5] = {32'd1, 32'd5};
                uut.workers[gw].u_worker.rom[6] = {32'd4, 32'd6};*/
					 
					 uut.workers[gw].u_worker.rom[0] = {32'd1, 32'd2}; 
                uut.workers[gw].u_worker.rom[1] = {32'd3, 32'd4};
                uut.workers[gw].u_worker.rom[2] = {32'd6, 32'd5}; 
                uut.workers[gw].u_worker.rom[3] = {32'd7, 32'd8};
                uut.workers[gw].u_worker.rom[4] = {32'd10, 32'd9}; 
                uut.workers[gw].u_worker.rom[5] = {32'd11, 32'd12};
                uut.workers[gw].u_worker.rom[6] = {32'd13, 32'd14};
					 
					 


                
					 
            end
        end
    endgenerate

    initial begin
        // 2. Reset e Inicialização
        clk = 0;
        rst = 1; 
        start_global = 0; 
        k_input = 32'd9; // K de teste
        timeout_counter = 0;

        #100 rst = 0;
        #20 start_global = 1; 
        #10 start_global = 0; 
    end

    // Monitoramento
    always @(posedge clk) begin
        if (!all_finished && start_global == 0 && rst == 0) begin
            timeout_counter = timeout_counter + 1;
            if (timeout_counter > 1000000) begin
                $display("\n>>> T=%0t | ERRO: Timeout atingido!", $time);
                $finish;
            end
        end

        if (all_finished) begin
            $display("\n==================================================");
            $display("REPORTE FINAL DO GRAFO");
            $display("==================================================");
            $display("Arestas que permaneceram no Grafo (Melhor Mascara):");
            $display("--------------------------------------------------");
            
            for (integer e = 0; e < 512; e = e + 1) begin
                if (uut.best_mask[e] == 1'b0) begin
                    // Usamos o worker 0 apenas como referencia de leitura no TB. Como é 0 (constante), não dá erro!
                    if (uut.workers[0].u_worker.rom[e] != 64'd0) begin
                        $display("Aresta[%3d]: ( %2d, %2d)", 
                                 e, uut.workers[0].u_worker.rom[e][63:32], uut.workers[0].u_worker.rom[e][31:0]);
                    end
                end
            end
            $display("--------------------------------------------------");
            $display("Simulacao finalizada em T = %0t", $time);
            $display("==================================================\n");
            $finish;
        end
    end
endmodule