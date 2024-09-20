`default_nettype none
`timescale 1ns/1ns

// MEMORY CONTROLLER，内存控制
// > Receives memory requests from all cores，
// > Throttles requests based on limited external memory bandwidth，基于有限的外部内存带宽对请求进行节流
// > Waits for responses from external memory and distributes them back to cores，等待外部内存的响应，然后将响应分发回各个核心。
module controller #(
    parameter ADDR_BITS = 8, // 地址位宽 
    parameter DATA_BITS = 16,// 数据位宽
    parameter NUM_CONSUMERS = 4, // The number of consumers accessing memory through this controller，消费者数量
    parameter NUM_CHANNELS = 1,  // The number of concurrent channels available to send requests to global memory，并发通道数量 
    parameter WRITE_ENABLE = 1   // Whether this memory controller can write to memory (program memory is read-only)，写使能
) (
    input wire clk,
    input wire reset,

    // Consumer Interface (Fetchers / LSUs)
    input reg [NUM_CONSUMERS-1:0] consumer_read_valid, // 读请求有效
    input reg [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0], // 读请求地址
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready, // 读请求准备好
    output reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0], // 读请求数据
    input reg [NUM_CONSUMERS-1:0] consumer_write_valid, // 写请求有效
    input reg [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0], // 写请求地址
    input reg [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0], // 写请求数据
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready, // 写请求准备好

    // Memory Interface (Data / Program)
    output reg [NUM_CHANNELS-1:0] mem_read_valid, // 内存读请求有效信号
    output reg [ADDR_BITS-1:0] mem_read_address [NUM_CHANNELS-1:0], // 内存读请求地址
    input reg [NUM_CHANNELS-1:0] mem_read_ready, // 内存读请求准备好信号
    input reg [DATA_BITS-1:0] mem_read_data [NUM_CHANNELS-1:0], // 内存读响应数据
    output reg [NUM_CHANNELS-1:0] mem_write_valid, // 内存写请求有效信号
    output reg [ADDR_BITS-1:0] mem_write_address [NUM_CHANNELS-1:0], // 内存写请求地址
    output reg [DATA_BITS-1:0] mem_write_data [NUM_CHANNELS-1:0], // 内存写请求数据
    input reg [NUM_CHANNELS-1:0] mem_write_ready // 内存写请求准备好信号
);
    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    // Keep track of state for each channel and which jobs each channel is handling，为每个通道和每个通道正在处理的作业跟踪状态
    reg [2:0] controller_state [NUM_CHANNELS-1:0];
    reg [$clog2(NUM_CONSUMERS)-1:0] current_consumer [NUM_CHANNELS-1:0]; // Which consumer is each channel currently serving，每个通道当前服务的消费者是谁
    reg [NUM_CONSUMERS-1:0] channel_serving_consumer; // Which channels are being served? Prevents many workers from picking up the same request.，哪些通道正在服务？防止多个工作人员同时处理同一请求。

    // State machine for each channel，每个通道的状态机
    // 状态机一次只能处理一个读或写请求，只能读或写一个地址的数据，如果有多个读或写请求，会在下一个时钟周期处理
    always @(posedge clk) begin
        if (reset) begin 
            mem_read_valid <= 0;
            mem_read_address <= 0;

            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;

            current_consumer <= 0;
            controller_state <= 0;

            channel_serving_consumer = 0;
        end else begin 
            // For each channel, we handle processing concurrently，对于每个通道，我们同时处理处理
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin 
                case (controller_state[i])
                    IDLE: begin
                        // While this channel is idle, cycle through consumers looking for one with a pending request，当此通道空闲时，循环遍历消费者，查找具有挂起请求的消费者
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin 
                            if (consumer_read_valid[j] && !channel_serving_consumer[j]) begin // 某个消费者的读请求有效且该通道未被服务
                                channel_serving_consumer[j] = 1; // 该通道设置为正在服务
                                current_consumer[i] <= j; // 当前通道服务的消费者为j

                                mem_read_valid[i] <= 1; // 读请求有效
                                mem_read_address[i] <= consumer_read_address[j]; // 读请求地址
                                controller_state[i] <= READ_WAITING; // 状态转为等待读

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                // 一旦找到挂起请求，使用此通道接收请求并停止查找请求（过河拆桥）
                                break;
                            end else if (consumer_write_valid[j] && !channel_serving_consumer[j]) begin // 某个消费者的写请求有效且该通道未被服务
                                channel_serving_consumer[j] = 1; // 该通道设置为正在服务
                                current_consumer[i] <= j; // 当前通道服务的消费者为j

                                mem_write_valid[i] <= 1; // 写请求有效
                                mem_write_address[i] <= consumer_write_address[j]; // 写请求地址
                                mem_write_data[i] <= consumer_write_data[j]; // 写请求数据
                                controller_state[i] <= WRITE_WAITING; // 状态转为等待写

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                // 一旦找到挂起请求，使用此通道接收请求并停止查找请求（过河拆桥）
                                break;
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Wait for response from memory for pending read request，等待内存的响应
                        if (mem_read_ready[i]) begin // 内存读请求准备好
                            mem_read_valid[i] <= 0; // 读请求无效
                            consumer_read_ready[current_consumer[i]] <= 1; // 消费者读请求准备好
                            consumer_read_data[current_consumer[i]] <= mem_read_data[i]; // 消费者读请求数据
                            controller_state[i] <= READ_RELAYING; // 状态转为读中继
                        end
                    end
                    WRITE_WAITING: begin 
                        // Wait for response from memory for pending write request，等待内存的响应
                        if (mem_write_ready[i]) begin // 内存写请求准备好
                            mem_write_valid[i] <= 0; // 写请求无效
                            consumer_write_ready[current_consumer[i]] <= 1; // 消费者写请求准备好
                            controller_state[i] <= WRITE_RELAYING; // 状态转为写中继
                        end
                    end
                    // Wait until consumer acknowledges it received response, then reset，等待消费者确认已收到响应，然后重置
                    READ_RELAYING: begin
                        if (!consumer_read_valid[current_consumer[i]]) begin // 消费者读请求无效
                            channel_serving_consumer[current_consumer[i]] = 0; // 该通道设置为未服务
                            consumer_read_ready[current_consumer[i]] <= 0; // 消费者读请求设置为未准备好
                            controller_state[i] <= IDLE; // 状态转为空闲
                        end
                    end
                    WRITE_RELAYING: begin 
                        if (!consumer_write_valid[current_consumer[i]]) begin // 消费者写请求无效
                            channel_serving_consumer[current_consumer[i]] = 0; // 该通道设置为未服务
                            consumer_write_ready[current_consumer[i]] <= 0; // 消费者写请求设置为未准备好
                            controller_state[i] <= IDLE; // 状态转为空闲
                        end
                    end
                endcase
            end
        end
    end
endmodule
