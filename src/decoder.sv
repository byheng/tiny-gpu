`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER
// > Decodes an instruction into the control signals necessary to execute it，将指令解码为执行所需的控制信号
// > Each core has it's own decoder，每个核都有自己的解码器
module decoder (
    input wire clk,
    input wire reset,

    input reg [2:0] core_state, // Current state, 3'b010: DECODE
    input reg [15:0] instruction,
    
    // Instruction Signals
    output reg [3:0] decoded_rd_address, 
    output reg [3:0] decoded_rs_address,
    output reg [3:0] decoded_rt_address,
    output reg [2:0] decoded_nzp,
    output reg [7:0] decoded_immediate,
    
    // Control Signals
    output reg decoded_reg_write_enable,           // Enable writing to a register, 用于写入寄存器
    output reg decoded_mem_read_enable,            // Enable reading from memory, 用于从内存读取
    output reg decoded_mem_write_enable,           // Enable writing to memory, 用于写入内存
    output reg decoded_nzp_write_enable,           // Enable writing to NZP register, 用于写入NZP寄存器
    output reg [1:0] decoded_reg_input_mux,        // Select input to register, 00: ALU output, 01: Memory output, 10: Immediate
    output reg [1:0] decoded_alu_arithmetic_mux,   // Select arithmetic operation, 00: ADD, 01: SUB, 10: MUL, 11: DIV
    output reg decoded_alu_output_mux,             // Select operation in ALU, 0: ALU output, 1: NZP register
    output reg decoded_pc_mux,                     // Select source of next PC, 0: PC + 1, 1: PC + immediate, 2: Register

    // Return (finished executing thread)
    output reg decoded_ret
);
    localparam NOP = 4'b0000,
        BRnzp = 4'b0001,
        CMP = 4'b0010,
        ADD = 4'b0011,
        SUB = 4'b0100,
        MUL = 4'b0101,
        DIV = 4'b0110,
        LDR = 4'b0111,
        STR = 4'b1000,
        CONST = 4'b1001,
        RET = 4'b1111;

    always @(posedge clk) begin 
        if (reset) begin 
            // Reset all Instruction signals on every reset, 每次复位时重置所有指令信号
            decoded_rd_address <= 0;
            decoded_rs_address <= 0;
            decoded_rt_address <= 0;
            decoded_immediate <= 0;
            decoded_nzp <= 0;
            // Control signals reset on every reset, 每次复位时控制信号重置
            decoded_reg_write_enable <= 0;
            decoded_mem_read_enable <= 0;
            decoded_mem_write_enable <= 0;
            decoded_nzp_write_enable <= 0;
            decoded_reg_input_mux <= 0;
            decoded_alu_arithmetic_mux <= 0;
            decoded_alu_output_mux <= 0;
            decoded_pc_mux <= 0;
            decoded_ret <= 0;
        end else begin 
            // Decode when core_state = DECODE
            if (core_state == 3'b010) begin 
                // Get instruction signals from instruction every time, 每次从指令中获取指令信号
                decoded_rd_address <= instruction[11:8];
                decoded_rs_address <= instruction[7:4];
                decoded_rt_address <= instruction[3:0];
                decoded_immediate <= instruction[7:0];
                decoded_nzp <= instruction[11:9];

                // Control signals reset on every decode and set conditionally by instruction, 每次解码时控制信号重置，并根据指令有条件地设置
                decoded_reg_write_enable <= 0;
                decoded_mem_read_enable <= 0;
                decoded_mem_write_enable <= 0;
                decoded_nzp_write_enable <= 0;
                decoded_reg_input_mux <= 0;
                decoded_alu_arithmetic_mux <= 0;
                decoded_alu_output_mux <= 0;
                decoded_pc_mux <= 0;
                decoded_ret <= 0;

                // Set the control signals for each instruction
                case (instruction[15:12])
                    NOP: begin 
                        // no-op
                    end
                    BRnzp: begin 
                        decoded_pc_mux <= 1;
                    end
                    CMP: begin 
                        decoded_alu_output_mux <= 1;
                        decoded_nzp_write_enable <= 1;
                    end
                    ADD: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b00;
                    end
                    SUB: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b01;
                    end
                    MUL: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b10;
                    end
                    DIV: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b11;
                    end
                    LDR: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b01;
                        decoded_mem_read_enable <= 1;
                    end
                    STR: begin 
                        decoded_mem_write_enable <= 1;
                    end
                    CONST: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b10;
                    end
                    RET: begin 
                        decoded_ret <= 1;
                    end
                endcase
            end
        end
    end
endmodule
