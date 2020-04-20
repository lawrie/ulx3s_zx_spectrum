module rom (
  input                    clk,
  input [A_WIDTH-1:0]      addr, 
  output reg [D_WIDTH-1:0] dout
);

  parameter A_WIDTH = 12;
  parameter D_WIDTH = 8;
  parameter MEM_INIT_FILE = "";
   
  reg [D_WIDTH-1:0] rom [0:2**A_WIDTH-1];

  initial
    if (MEM_INIT_FILE != "")
      $readmemh(MEM_INIT_FILE, rom);
   
  always @(posedge clk)
    dout <= rom[addr];
   
endmodule
