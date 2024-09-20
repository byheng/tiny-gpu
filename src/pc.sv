`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER
// > Calculates the next PC for each thread to update to (but currently we assume all threads
//   update to the same PC and don't support branch divergence)，计算每个线程要更新到的下一个PC（但目前我们假设所有线程都更新到相同的PC，不支持分支分歧）
// > Currently, each thread in each core has it's own calculation for next PC，每个核中的每个线程都有自己的下一个PC计算
// > The NZP register value is set by the CMP instruction (based on >/=/< comparison) to 
//   initiate the BRnzp instruction for branching， // NZP寄存器的值由CMP指令设置（基于>/=/<比较）以启动BRnzp指令进行分支
module pc #(
    parameter DATA_MEM_DATA_BITS = 8, // Data Memory Data Bits
    parameter PROGRAM_MEM_ADDR_BITS = 8 // Program Memory Address Bits
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some PCs will be inactive，如果当前块的线程少于块大小，则某些PC将处于非活动状态

    // State
    input reg [2:0] core_state, // Current state, 3'b101: EXECUTE, 3'b110: UPDATE

    // Control Signals
    input reg [2:0] decoded_nzp, // NZP register value to compare with ALU output，与ALU输出进行比较的NZP寄存器值
    input reg [DATA_MEM_DATA_BITS-1:0] decoded_immediate, // Immediate value for BRnzp instruction，BRnzp指令的立即数
    input reg decoded_nzp_write_enable, // Write to NZP register on CMP instruction，CMP指令时写入NZP寄存器
    input reg decoded_pc_mux, // PC Mux, 0: PC + 1, 1: Immediate，PC多路器，0: PC + 1, 1: 立即数

    // ALU Output - used for alu_out[2:0] to compare with NZP register，用于与NZP寄存器比较的ALU输出
    input reg [DATA_MEM_DATA_BITS-1:0] alu_out,

    // Current & Next PCs
    input reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);
    reg [2:0] nzp; // 

    always @(posedge clk) begin
        if (reset) begin
            nzp <= 3'b0;
            next_pc <= 0;
        end else if (enable) begin
            // Update PC when core_state = EXECUTE, 当core_state = EXECUTE时更新PC
            if (core_state == 3'b101) begin  // 3'b101: EXECUTE
                if (decoded_pc_mux == 1) begin  // PC Mux, 0: PC + 1, 1: Immediate
                    if (((nzp & decoded_nzp) != 3'b0)) begin 
                        // On BRnzp instruction, branch to immediate if NZP case matches previous CMP, 在BRnzp指令上，如果NZP情况与之前的CMP匹配，则分支到立即数
                        next_pc <= decoded_immediate; // Branch to immediate，分支到立即数
                    end else begin 
                        // Otherwise, just update to PC + 1 (next line)，否则，只更新到PC + 1（下一行）
                        next_pc <= current_pc + 1;
                    end
                end else begin 
                    // By default update to PC + 1 (next line)，默认更新到PC + 1（下一行）
                    next_pc <= current_pc + 1;
                end
            end   

            // Store NZP when core_state = UPDATE，当core_state = UPDATE时存储NZP
            if (core_state == 3'b110) begin 
                // Write to NZP register on CMP instruction，CMP指令时写入NZP寄存器
                if (decoded_nzp_write_enable) begin
                    nzp[2] <= alu_out[2];
                    nzp[1] <= alu_out[1];
                    nzp[0] <= alu_out[0];
                end
            end      
        end
    end

endmodule
