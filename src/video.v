`default_nettype none
module video (
  input        clk,
  input        reset,

  output [3:0] vga_r,
  output [3:0] vga_b,
  output [3:0] vga_g,
  output       vga_hs,
  output       vga_vs,
  output       vga_de,
  input  [7:0] vga_data,
  output [12:0] vga_addr,
);

  parameter HA = 640;
  parameter HS  = 96;
  parameter HFP = 16;
  parameter HBP = 48;
  parameter HT  = HA + HS + HFP + HBP;

  parameter VA = 480;
  parameter VS  = 2;
  parameter VFP = 11;
  parameter VBP = 31;
  parameter VT  = VA + VS + VFP + VBP;

  reg [9:0] hc = 0;
  reg [9:0] vc = 0;

  always @(posedge clk) begin
    if (hc == HT - 1) begin
      hc <= 0;
      if (vc == VT - 1) vc <= 0;
      else vc <= vc + 1;
    end else hc <= hc + 1;
  end

  assign vga_hs = !(hc >= HA + HFP && hc < HA + HFP + HS);
  assign vga_vs = !(vc >= VA + VFP && vc < VA + VFP + VS);
  assign vga_de = !(hc > HA || vc > VA);

  wire [7:0] x = (hc - 64) >> 1;
  wire [7:0] y = (vc - 48) >> 1;

  assign vga_addr = {y[7:6], y[2:0], y[5:3], x[7:3]};

  wire hBorder = (hc < 64 || hc >= HA - 64);
  wire vBorder = (vc < 48 || vc >= VA - 48);
  wire border = hBorder || vBorder;

  wire red = 0;
  wire green = !border && vga_data[x[2:0]];
  wire blue = border;

  assign vga_r = !vga_de ? 4'b0 : {4{red}};
  assign vga_g = !vga_de ? 4'b0 : {4{green}};
  assign vga_b = !vga_de ? 4'b0 : {4{blue}};

endmodule

