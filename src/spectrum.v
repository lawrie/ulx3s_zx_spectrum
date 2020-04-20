`default_nettype none
module Spectrum (
  input         clk25_mhz,
  // Buttons
  input [6:0]   btn,
  // VGA
  output        videoR0,
  output        videoG0,
  output        videoB0,
  output        videoR1,
  output        videoG1,
  output        videoB1,
  output        hSync,
  output        vSync,
  // HDMI
  output [3:0]  gpdi_dp,
  output [3:0]  gpdi_dn,
  // Keyboard
  output        usb_fpga_pu_dp,
  output        usb_fpga_pu_dn,
  inout         ps2Clk,
  inout         ps2Data,
  // Leds
  output [7:0]  leds,
  output [15:0] diag
);

   wire          n_WR;
   wire          n_RD;
   wire [15:0]   cpuAddress;
   wire [7:0]    cpuDataOut;
   wire [7:0]    cpuDataIn;
   wire          n_memWR;
   wire          n_memRD;
   wire          n_ioWR;
   wire          n_ioRD;
   wire          n_MREQ;
   wire          n_IORQ;
   wire          n_romCS;
   wire          n_ramCS;

   reg [5:0]     cpuClkCount = 0;
   reg           cpuClock;

   reg           ram8kWritten = 0;

   // ===============================================================
   // System Clock generation
   // ===============================================================
   wire clk125, clk;

   pll pll_i (
     .clkin(clk25_mhz),
     .clkout0(clk125),
     .clkout1(clk)
   );

   // ===============================================================
   // Reset generation
   // ===============================================================
   reg [15:0] pwr_up_reset_counter = 0;
   wire       pwr_up_reset_n = &pwr_up_reset_counter;

   always @(posedge clk)
     begin
       if (!pwr_up_reset_n)
         pwr_up_reset_counter <= pwr_up_reset_counter + 1;
     end

   wire n_hard_reset = pwr_up_reset_n & btn[0];

   // ===============================================================
   // CPU
   // ===============================================================
   tv80n
     #(
       .Mode(1),
       .T2Write(1),
       .IOWait(0)
       )
   cpu1
     (
      .reset_n(n_hard_reset),
      .clk(cpuClock),
      .wait_n(1'b 1),
      .int_n(1'b 1),
      .nmi_n(1'b 1),
      .busrq_n(1'b 1),
      .mreq_n(n_MREQ),
      .iorq_n(n_IORQ),
      .rd_n(n_RD),
      .wr_n(n_WR),
      .A(cpuAddress),
      .di(cpuDataIn),
      .do(cpuDataOut));

   // ===============================================================
   // ROM 
   // ===============================================================
   
   wire [7:0] romOut;

   rom #(.MEM_INIT_FILE(""), .A_WIDTH(13)) rom16 (
     .clk(clk),
     .addr(cpuAddress[12:0]),
     .dout(romOut)
   );

   // ===============================================================
   // RAM
   // ===============================================================
   wire [7:0] ramOut;
   
   dpram ram48 (
     .clk_a(clk),
     .we_a(!n_ramCS & !n_memWR),
     .addr_a(cpuAddress),
     .din_a(cpuDataOut),
     .dout_a(ramOut)
   );

   // ===============================================================
   // Keyboard
   // ===============================================================
   
   // pull-ups for us2 connector 
   assign usb_fpga_pu_dp = 1;
   assign usb_fpga_pu_dn = 1;

   // ===============================================================
   // VGA
   // ===============================================================
   reg clk_vga = clk;
   reg clk_hdmi = clk125;

   wire vga_blank;

   // Convert VGA to HDMI
   HDMI_out vga2dvid (
     .pixclk(clk_vga),
     .pixclk_x5(clk_hdmi),
     .red({videoR1, videoR0, 6'b0}),
     .green({videoG1, videoG0, 6'b0}),
     .blue({videoB1, videoB0, 6'b0}),
     .vde(!vga_blank),
     .hSync(hSync),
     .vSync(vSync),
     .gpdi_dp(gpdi_dp),
     .gpdi_dn(gpdi_dn)
   );

   // ===============================================================
   // MEMORY READ/WRITE LOGIC
   // ===============================================================

   assign n_ioWR = n_WR | n_IORQ;
   assign n_memWR = n_WR | n_MREQ;
   assign n_ioRD = n_RD | n_IORQ;
   assign n_memRD = n_RD | n_MREQ;

   // ===============================================================
   // CHIP SELECTS
   // ===============================================================

   assign n_romCS = cpuAddress[15:13] != 0;
   assign n_ramCS = 1'b 0; // Always selected

   // ===============================================================
   // Memory multiplexing
   // ===============================================================

   assign cpuDataIn =  n_romCS == 1'b 0 ? romOut              :
                       n_ramCS == 1'b 0 ? ramOut              :
                                          8'h FF;

   // CPU clock generation
   always @(posedge clk) begin
      if(cpuClkCount < 2) begin
         // 4 = 10MHz, 3 = 12.5MHz, 2=16.6MHz, 1=25MHz
         cpuClkCount <= cpuClkCount + 1;
      end
      else begin
         cpuClkCount <= {6{1'b0}};
      end
      if(cpuClkCount < 1) begin
         // 2 when 10MHz, 2 when 12.5MHz, 2 when 16.6MHz, 1 when 25MHz
         cpuClock <= 1'b 0;
      end
      else begin
         cpuClock <= 1'b 1;
      end
   end

   // ===============================================================
   // Leds
   // ===============================================================

   wire led1 = 0;
   wire led2 = 0;
   wire led3 = n_WR;
   wire led4 = !n_hard_reset;

   assign leds = {4'b0, led4, led3, led2, led1};
   assign diag = cpuAddress;
   
endmodule

