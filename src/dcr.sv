`default_nettype none
`timescale 1ns/1ns

// DEVICE CONTROL REGISTER
// > Used to configure high-level settings
// > In this minimal example, the DCR is used to configure the number of threads to run for the kernel
module dcr (
    input wire clk,
    input wire reset,

    input wire device_control_write_enable, // 设备控制写使能信号
    input wire [7:0] device_control_data, // 设备控制数据
    output wire [7:0] thread_count // 线程数
);
    // Store device control data in dedicated register, 将设备控制数据存储在专用寄存器中
    reg [7:0] device_conrol_register; // 设备控制寄存器
    assign thread_count = device_conrol_register[7:0]; // 线程数

    always @(posedge clk) begin
        if (reset) begin
            device_conrol_register <= 8'b0;
        end else begin
            if (device_control_write_enable) begin 
                device_conrol_register <= device_control_data; // Write device control data to register, 将设备控制数据写入寄存器
            end
        end
    end
endmodule