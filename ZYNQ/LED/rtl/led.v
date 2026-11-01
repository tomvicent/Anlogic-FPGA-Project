module led(
    input key,      //输入按键
    output led      //输出:LED  
);

assign led = ~key;

endmodule