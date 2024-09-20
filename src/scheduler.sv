`default_nettype none
`timescale 1ns/1ns

// SCHEDULER, 调度程序
// > Manages the entire control flow of a single compute core processing 1 block，管理单个计算核心的整个控制流,负责处理一个块中的多个线程
// 1. FETCH - Retrieve instruction at current program counter (PC) from program memory, 从程序存储器中检索当前程序计数器（PC）处的指令
// 2. DECODE - Decode the instruction into the relevant control signals, 将指令解码为相关的控制信号
// 3. REQUEST - If we have an instruction that accesses memory, trigger the async memory requests from LSUs, 如果有一个访问内存的指令，触发来自LSU的异步内存请求
// 4. WAIT - Wait for all async memory requests to resolve (if applicable), 等待所有异步内存请求解决（如果适用）
// 5. EXECUTE - Execute computations on retrieved data from registers / memory, 在从寄存器/内存检索的数据上执行计算
// 6. UPDATE - Update register values (including NZP register) and program counter, 更新寄存器值（包括NZP寄存器）和程序计数器
// > Each core has it's own scheduler where multiple threads can be processed with
//   the same control flow at once.,每个核心都有自己的调度程序，可以同时处理多个线程，具有相同的控制流
// > Technically, different instructions can branch to different PCs, requiring "branch divergence." In
//   this minimal implementation, we assume no branch divergence (naive approach for simplicity),技术上，不同的指令可以分支到不同的PC，需要“分支分歧”。在这个最小的实现中，我们假设没有分支分歧（简单的方法）
module scheduler #(
    parameter THREADS_PER_BLOCK = 4 // 每个块中的线程数，默认为 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // Control Signals
    input reg decoded_mem_read_enable, // 读取内存使能
    input reg decoded_mem_write_enable, // 写入内存使能
    input reg decoded_ret, // 返回指令

    // Memory Access State
    input reg [2:0] fetcher_state, // 表示取指令的状态
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0], // 表示LSU的状态,是一个数组，包含 THREADS_PER_BLOCK 个 2 位寄存器，用于表示每个线程的加载/存储单元（LSU）的状态。

    // Current & Next PC
    output reg [7:0] current_pc, // 当前PC
    input reg [7:0] next_pc [THREADS_PER_BLOCK-1:0], // 下一个PC

    // Execution State
    output reg [2:0] core_state, // 核心状态
    output reg done // 完成标志
);
    localparam IDLE = 3'b000, // Waiting to start, 等待开始
        FETCH = 3'b001,       // Fetch instructions from program memory, 从程序存储器中获取指令
        DECODE = 3'b010,      // Decode instructions into control signals, 将指令解码为控制信号
        REQUEST = 3'b011,     // Request data from registers or memory, 从寄存器或内存请求数据
        WAIT = 3'b100,        // Wait for response from memory if necessary, 如果需要，等待内存的响应
        EXECUTE = 3'b101,     // Execute ALU and PC calculations, 执行ALU和PC计算
        UPDATE = 3'b110,      // Update registers, NZP, and PC, 更新寄存器、NZP和PC
        DONE = 3'b111;        // Done executing this block, 完成执行此块
    
    always @(posedge clk) begin 
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
        end else begin 
            case (core_state)
                IDLE: begin
                    // Here after reset (before kernel is launched, or after previous block has been processed)
                    // 程序复位后（在启动内核之前，或在处理完上一个块之后），在这里
                    if (start) begin 
                        // Start by fetching the next instruction for this block based on PC
                        // 根据PC获取此块的下一条指令开始
                        core_state <= FETCH;
                    end
                end
                FETCH: begin 
                    // Move on once fetcher_state = FETCHED
                    if (fetcher_state == 3'b010) begin 
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    // Decode is synchronous so we move on after one cycle, 解码是同步的，所以我们在一个周期后继续
                    core_state <= REQUEST;
                end
                REQUEST: begin 
                    // Request is synchronous so we move on after one cycle, 请求是同步的，所以我们在一个周期后继续
                    core_state <= WAIT;
                end
                WAIT: begin
                    // Wait for all LSUs to finish their request before continuing, 在继续之前等待所有LSU完成请求
                    reg any_lsu_waiting = 1'b0;
                    for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                        // Make sure no lsu_state = REQUESTING or WAITING
                        if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin // 2'b01: REQUESTING, 2'b10: WAITING
                            any_lsu_waiting = 1'b1;
                            break;
                        end
                    end

                    // If no LSU is waiting for a response, move onto the next stage, 如果没有LSU在等待响应，则继续下一阶段
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    // Execute is synchronous so we move on after one cycle
                    core_state <= UPDATE;
                end
                UPDATE: begin 
                    if (decoded_ret) begin 
                        // If we reach a RET instruction, this block is done executing, 如果我们获得RET指令，这个块执行完毕
                        done <= 1;
                        core_state <= DONE;
                    end else begin 
                        // TODO: Branch divergence. For now assume all next_pc converge，分支分歧。现在假设所有的next_pc都会收敛
                        current_pc <= next_pc[THREADS_PER_BLOCK-1];

                        // Update is synchronous so we move on after one cycle
                        core_state <= FETCH;
                    end
                end
                DONE: begin 
                    // no-op
                end
            endcase
        end
    end
endmodule
