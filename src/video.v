`default_nettype none
module video (
  input         clk,
  input         reset,
  output [3:0]  vga_r,
  output [3:0]  vga_b,
  output [3:0]  vga_g,
  output        vga_hs,
  output        vga_vs,
  output        vga_de,
  input  [7:0]  vga_data,
  output [12:0] vga_addr,
  input  [7:0]  attr_data,
  output [12:0] attr_addr,
  output        n_int,
  input  [2:0]  border_color
);

  parameter HA = 640;
  parameter HS  = 96;
  parameter HFP = 16;
  parameter HBP = 48;
  parameter HT  = HA + HS + HFP + HBP;
  parameter HB = 64;

  parameter VA = 480;
  parameter VS  = 2;
  parameter VFP = 11;
  parameter VBP = 31;
  parameter VT  = VA + VS + VFP + VBP;
  parameter VB = 48;

  reg [9:0] hc = 0;
  reg [9:0] vc = 0;
  reg INT = 0;
  reg[5:0] intCnt = 1;
  reg [5:0] flash_cnt = 0;

  assign n_int = !INT;

  always @(posedge clk) begin
    if (hc == HT - 1) begin
      hc <= 0;
      if (vc == VT - 1) vc <= 0;
      else vc <= vc + 1;
    end else hc <= hc + 1;
    if (hc == HA + HFP && vc == VA + VFP) begin
      INT <= 1;
      flash_cnt <= flash_cnt + 1;
    end
    if (INT) intCnt <= intCnt + 1;
    if (!intCnt) INT <= 0;
  end

  assign vga_hs = !(hc >= HA + HFP && hc < HA + HFP + HS);
  assign vga_vs = !(vc >= VA + VFP && vc < VA + VFP + VS);
  assign vga_de = !(hc > HA || vc > VA);

  wire [7:0] x = (hc - HB) >> 1;
  wire [7:0] y = (vc - VB) >> 1;

  assign vga_addr = {y[7:6], y[2:0], y[5:3], x[7:3]};
  assign attr_addr = 13'h1800 + {3'b0, y[7:3], x[7:3]};

  // Wait one clock cycle for attr_data to be available
  reg [7:0] attr;
  always @(posedge clk) if (hc[0]) attr <= attr_data;

  wire hBorder = (hc < HB || hc >= HA - HB);
  wire vBorder = (vc < VB || vc >= VA - VB);
  wire border = hBorder || vBorder;

  wire [2:0] ink = attr[2:0];
  wire [2:0] paper = attr[5:3];
  wire bright = attr[6];
  wire flash = attr[7];
  wire flashing = flash && flash_cnt[5];

  wire ink_red = flashing ? paper[1] : ink[1];
  wire ink_green = flashing ? paper[2] : ink[2];
  wire ink_blue = flashing ? paper[0] : ink[0];

  wire paper_red = flashing ? ink[1] :paper[1];
  wire paper_green = flashing ? ink[2] : paper[2];
  wire paper_blue = flashing ? ink[0] : paper[0];

  // Wait a clock cycle for vga_data to be available
  reg pixel;
  always @(posedge clk) if (hc[0]) pixel <= vga_data[~x[2:0]];

  wire [3:0] red = border ? {4{border_color[1]}} : ({1'b0, {3{pixel ? ink_red : paper_red}}} << bright);
  wire [3:0] green = border ? {4{border_color[2]}} : ({1'b0, {3{pixel ? ink_green : paper_green}}} << bright) ;
  wire [3:0] blue = border ? {4{border_color[0]}} : ({1'b0, {3{pixel ? ink_blue : paper_blue}}} << bright);

  assign vga_r = !vga_de ? 4'b0 : red;
  assign vga_g = !vga_de ? 4'b0 : green;
  assign vga_b = !vga_de ? 4'b0 : blue;

endmodule

