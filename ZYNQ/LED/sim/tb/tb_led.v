`timescale 1ns/1ns
module tb_led();
reg key;
wire led;

initial begin
    #500
    key <= 1'b1;
    #500
    key <= 1'b0;
    #500
    key <= 1'b1;
    #500
    key <= 1'b0;


end

led u_led(
    .key(key),
    .led(led)
);

endmodule