# K-Vertex Cover Hardware Accelerator on FPGA

Este repositório contém a implementação em **Verilog** de um acelerador de hardware dedicado para resolver o problema matemático NP-Hard conhecido como **K-Vertex Cover** (Cobertura de Vértices). 

O projeto foi projetado para ser altamente paralelo, utilizando uma arquitetura **Manager-Worker**, e sintetizado para a placa educacional **Altera/Intel DE1 (Cyclone II)**.

---

## 📌 Sobre o Projeto

O K-Vertex Cover é um problema clássico de otimização em grafos. O objetivo é descobrir se é possível cobrir todas as arestas de um grafo utilizando, no máximo, `K` vértices. 

Em vez de rodar um algoritmo sequencial em um processador comum (C/Python), este projeto move o processador para o hardware. A FPGA instancia múltiplos "trabalhadores" (Workers) que avaliam diferentes combinações de vértices simultaneamente, resultando em um tempo de resposta determinístico e ultrarrápido (na casa dos microssegundos).

---

## ⚙️ Arquitetura do Hardware

* **Topologia:** Manager-Worker. O módulo principal (Manager) gerencia uma fila circular (FIFO) e distribui os ramos da árvore de busca matemática.
* **Paralelismo:** Configurado com `NUM_WORKERS = 2` (expansível via parâmetros).
* **Armazenamento:** O grafo não usa memória RAM externa. Ele é injetado diretamente nos blocos de memória interna (BRAM) do chip através de um arquivo `.hex`.
* **Capacidade:** Suporta grafos de até 64 arestas (parâmetro `MAX_EDGES`).

---

## 📊 Resultados e Desempenho (Síntese)

O projeto foi sintetizado utilizando o **Intel Quartus II** para a FPGA **Cyclone II (EP2C20F484C7)**. Os resultados provam a alta eficiência do circuito dedicado em comparação com uma abordagem via software tradicional:

| Métrica | Resultado | Análise |
| :--- | :--- | :--- |
| **Uso Lógico (LEs)** | 9.184 / 18.752 (49%) | Ocupação equilibrada, suportando os 2 workers paralelos com folga. |
| **Uso de Memória (BRAM)** | 8.192 bits (~1 KB) | Extremamente eficiente. Representa apenas 3% da capacidade do chip. |
| **Pinos de I/O** | 68 / 315 (22%) | Uso enxuto de periféricos (Chaves, Displays e LEDs). |
| **Frequência Máxima (Fmax)**| 88,37 MHz | Excelente estabilidade. O circuito roda com folga acima dos 50 MHz nativos da placa DE1. |
| **Latência por Máscara** | ~200 ciclos de clock | Rende um tempo de validação de **~2,26 microssegundos** operando em frequência máxima. |

---

## 🛠️ Como Utilizar na Placa DE1

### 1. Configurando o Grafo
Crie ou modifique o arquivo `grafo.hex` na raiz do projeto. Ele deve conter a lista de arestas (um par de vértices por linha, em formato hexadecimal). Recompile o projeto no Quartus para injetar a nova memória no chip.

### 2. Mapeamento de Pinos (I/O Físico)
Após gravar o arquivo `.sof` na placa DE1, utilize os periféricos conforme abaixo:

* **SW[4:0] (Chaves 0 a 4):** Define o valor de **K** em binário (0 a 31).
* **HEX0 e HEX1:** Displays de 7 segmentos que exibem o valor de **K** escolhido em formato decimal.
* **KEY0 (Botão Azul):** `Reset`. Dá um pulso para limpar o estado anterior da máquina. (Lógica Active-Low tratada internamente no código).
* **SW9 (Chave 9):** `Start`. Levante para iniciar a computação do hardware. Abaixe após o término para ver o resultado negativo (se houver).
* **LEDG0 (LED Verde):** Acende instantaneamente se o hardware encontrar uma solução válida (SIM).
* **LEDR0 (LED Vermelho):** Acende se a busca esgotar todas as possibilidades e concluir que é impossível cobrir o grafo com aquele K (NÃO).

### Passo a Passo para Teste Físico:
1. Escolha o valor `K` nas chaves `SW[4:0]`.
2. Dê um clique no botão `KEY0` para resetar.
3. Levante a chave `SW9` (Start). O hardware executará a busca.
4. O LED Verde acenderá se a resposta for SIM. Caso a resposta seja NÃO, abaixe a chave `SW9` para visualizar o LED Vermelho acender.

---

## 🚀 Simulação no PC (Icarus Verilog)

Caso queira simular o comportamento das ondas de sinal antes de gravar na placa, você pode utilizar o **Icarus Verilog**:

```bash
# Compilar os arquivos Verilog
iverilog -o simulacao.vvp top_level.v worker_wrapper.v

# Executar a simulação
vvp simulacao.vvp
