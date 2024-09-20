`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > Retrieves the instruction at the current PC from global data memory，从全局数据内存中检索当前PC处的指令
// > Each core has it's own fetcher，每个核都有自己的取指器
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8, // 程序内存地址的位宽
    parameter PROGRAM_MEM_DATA_BITS = 16 // 程序内存数据的位宽
) (
    input wire clk,
    input wire reset,
    
    // Execution State
    input reg [2:0] core_state, // Current state, 3'b001: FETCH, 3'b010: DECODE
    input reg [7:0] current_pc,

    // Program Memory
    output reg mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher Output
    output reg [2:0] fetcher_state, // 3位状态机, 000: IDLE, 001: FETCHING, 010: FETCHED
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction // Instruction fetched from program memory，从程序存储器中获取的指令
);
    localparam IDLE = 3'b000, 
        FETCHING = 3'b001, 
        FETCHED = 3'b010;
    
    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            case (fetcher_state)
                IDLE: begin
                    // Start fetching when core_state = FETCH，当core_state = FETCH时开始取指
                    if (core_state == 3'b001) begin
                        fetcher_state <= FETCHING;
                        mem_read_valid <= 1;
                        mem_read_address <= current_pc;
                    end
                end
                FETCHING: begin
                    // Wait for response from program memory，等待来自程序存储器的响应
                    if (mem_read_ready) begin
                        fetcher_state <= FETCHED;
                        instruction <= mem_read_data; // Store the instruction when received
                        mem_read_valid <= 0;
                    end
                end
                FETCHED: begin
                    // Reset when core_state = DECODE
                    if (core_state == 3'b010) begin 
                        fetcher_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
