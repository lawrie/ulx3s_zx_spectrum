module dpram (
  // Port A
  input            clk_a,
  input            we_a,
  input [15:0]     addr_a,
  input [7:0]      din_a,
  output reg [7:0] dout_a,
  // Port B
  input            clk_b,
  input [15:0]     addr_b,
  output reg [7:0] dout_b,
  // Port C
  input            clk_c,
  input [15:0]     addr_c,
  output reg [7:0] dout_c            
);

  parameter MEM_INIT_FILE = "";
   
  reg [7:0] ram [0:49151];

  initial
    if (MEM_INIT_FILE != "")
      $readmemh(MEM_INIT_FILE, ram);
   
  always @(posedge clk_a) begin
    if (we_a)
      ram[addr_a] <= din_a;
    dout_a <= ram[addr_a];
  end

  always @(posedge clk_b) begin
    dout_b <= ram[addr_b];
  end

  always @(posedge clk_c) begin
    dout_c <= ram[addr_c];
  end
endmodule
