`default_nettype none
module Spectrum (
  input         clk25_mhz,
  // Buttons
  input [6:0]   btn,
  // VGA
  output [3:0]  red,
  output [3:0]  green,
  output [3:0]  blue,
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
  // Audio
  output [3:0]  audio_l,
  output [3:0]  audio_r,
  // ESP32 passthru
  input         ftdi_txd,
  output        ftdi_rxd,
  input         wifi_txd,
  output        wifi_rxd,  // SPI from ESP32
  input         wifi_gpio16,
  input         wifi_gpio5,

  inout  sd_clk, sd_cmd,
  inout   [3:0] sd_d,

  // Leds
  output [7:0]  leds,
  output reg [15:0] diag
);

  wire          n_WR;
  wire          n_RD;
  wire          n_INT;
  wire [15:0]   cpuAddress;
  wire [7:0]    cpuDataOut;
  wire [7:0]    cpuDataIn;
  wire          n_memWR;
  wire          n_memRD;
  wire          n_ioWR;
  wire          n_ioRD;
  wire          n_MREQ;
  wire          n_IORQ;
  wire          n_M1;
  wire          n_romCS;
  wire          n_ramCS;
  wire          n_kbdCS;
  
  reg [2:0]     border_color;
  wire          ula_we = ~cpuAddress[0] & ~n_IORQ & ~n_WR & n_M1;
  reg           old_ula_we;
  reg           sound;

  reg [2:0]     cpuClockCount;
  wire          cpuClock;
  wire          cpuClockEnable;

  // passthru to ESP32 micropython serial console
  assign wifi_rxd = ftdi_txd;
  assign ftdi_rxd = wifi_txd;

  // ===============================================================
  // System Clock generation
  // ===============================================================
  wire clk125, clk;

  pll pll_i (
    .clkin(clk25_mhz),
    .clkout0(clk125),
    .clkout1(clk),
    .clkout2(cpuClock)
  );

  // ===============================================================
  // Reset generation
  // ===============================================================
  reg [15:0] pwr_up_reset_counter = 0;
  wire       pwr_up_reset_n = &pwr_up_reset_counter;

  always @(posedge clk) begin
     if (!pwr_up_reset_n)
       pwr_up_reset_counter <= pwr_up_reset_counter + 1;
  end

  // ===============================================================
  // CPU
  // ===============================================================
  wire [15:0] pc;
  
  reg [7:0] R_cpu_control;
  wire loading = R_cpu_control[1];

  wire n_hard_reset = pwr_up_reset_n & btn[0] & ~R_cpu_control[0];

  tv80n cpu1 (
    .reset_n(n_hard_reset),
    .clk(cpuClock), // turbo mode 28MHz
    //.clk(cpuClockEnable), // normal mode 3.5MHz
    .wait_n(~loading),
    .int_n(n_INT),
    .nmi_n(1'b1),
    .busrq_n(1'b1),
    .mreq_n(n_MREQ),
    .m1_n(n_M1),
    .iorq_n(n_IORQ),
    .wr_n(n_WR),
    .A(cpuAddress),
    .di(cpuDataIn),
    .do(cpuDataOut),
    .pc(pc)
  );

  // ===============================================================
  // SPI Slave
  // ===============================================================
 
  wire spi_ram_wr, spi_ram_rd;
  wire [31:0] spi_ram_addr;
  wire [7:0] spi_ram_di;
  wire [7:0] ramOut;
  wire [7:0] spi_ram_do = ramOut;

  assign sd_d[3] = 1'bz; // FPGA pin pullup sets SD card inactive at SPI bus

  spirw_slave_v
  #(
    .c_sclk_capable_pin(1'b0),
    .c_addr_bits(32)
  )
  spirw_slave_v_inst
  (
    .clk(cpuClock),
    .csn(~wifi_gpio5),
    .sclk(wifi_gpio16),
    .mosi(sd_d[1]), // wifi_gpio4
    .miso(sd_d[2]), // wifi_gpio12
    .wr(spi_ram_wr),
    .rd(spi_ram_rd),
    .addr(spi_ram_addr),
    .data_in(spi_ram_do),
    .data_out(spi_ram_di)
  );

  always @(posedge cpuClock) begin
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hFF) begin
      R_cpu_control <= spi_ram_di;
    end
  end

  // ===============================================================
  // Border color and sound
  // ===============================================================

  always @(posedge cpuClock) begin
    old_ula_we <= ula_we;

    if (ula_we && !old_ula_we) begin
      border_color <= cpuDataOut[2:0];
      sound <= cpuDataOut[4];
    end
  end

  assign audio_l = {4{sound}};
  assign audio_r = {4{sound}};

  // ===============================================================
  // RAM
  // ===============================================================
  wire [7:0] vidOut;
  wire [12:0] vga_addr;
  wire [7:0] attrOut;
  wire [12:0] attr_addr;

  dpram
  #(
    .MEM_INIT_FILE("../roms/spectrum48.mem")
  )
  ram48 (
    .clk_a(cpuClock),
    .we_a(loading ? spi_ram_wr  && spi_ram_addr[31:24] == 8'h00 : !n_ramCS & !n_memWR),
    .addr_a(loading ? spi_ram_addr[15:0] : cpuAddress),
    .din_a(loading ? spi_ram_di : cpuDataOut),
    .dout_a(ramOut),
    .clk_b(clk_vga),
    .addr_b({3'b010, vga_addr}),
    .dout_b(vidOut)
  );

  // ===============================================================
  // Keyboard
  // ===============================================================
  wire [4:0]  key_data;
  wire [11:1] Fn;
  wire [2:0]  mod;
  wire [10:0] ps2_key;

    // Get PS/2 keyboard events
  ps2 ps2_kbd (
     .clk(clk),
     .ps2_clk(ps2Clk),
     .ps2_data(ps2Data),
     .ps2_key(ps2_key)
  );

  // Keyboard matrix
  keyboard the_keyboard (
    .reset(~n_hard_reset),
    .clk_sys(clk),
    .ps2_key(ps2_key),
    .addr(cpuAddress),
    .key_data(key_data),
    .Fn(Fn),
    .mod(mod)
  );

  // pull-ups for us2 connector 
  assign usb_fpga_pu_dp = 1;
  assign usb_fpga_pu_dn = 1;

  // ===============================================================
  // VGA
  // ===============================================================
  wire clk_vga = clk;
  wire clk_hdmi = clk125;
  wire vga_de;

  video vga (
    .clk(clk_vga),
    .vga_r(red),
    .vga_g(green),
    .vga_b(blue),
    .vga_de(vga_de),
    .vga_hs(hSync),
    .vga_vs(vSync),
    .vga_addr(vga_addr),
    .vga_data(vidOut),
    .n_int(n_INT),
    .border_color(border_color)
  );

  // Convert VGA to HDMI
  HDMI_out vga2dvid (
    .pixclk(clk_vga),
    .pixclk_x5(clk_hdmi),
    .red  ( {red,   {4{red[0]}}   }),
    .green( {green, {4{green[0]}} }),
    .blue ( {blue,  {4{blue[0]}}  }),
    .vde(vga_de),
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
  // Chip selects
  // ===============================================================

  assign n_kbdCS = (cpuAddress[0] | n_ioRD) == 1'b0 ? 1'b0 : 1'b1;
  assign n_romCS = cpuAddress[15:14] != 0;
  assign n_ramCS = !n_romCS;

  // ===============================================================
  // Memory decoding
  // ===============================================================

  assign cpuDataIn =  n_kbdCS == 1'b0 ? {3'b111, key_data} :
                      ramOut;
                      //n_romCS == 1'b0 ? romOut :
                      //n_ramCS == 1'b0 ? ramOut :
		      //                  8'hff;

  // ===============================================================
  // CPU clock enable
  // ===============================================================
   
  always @(posedge cpuClock) begin
    cpuClockCount <= cpuClockCount + 1;
  end

  assign cpuClockEnable = cpuClockCount[2]; // 3.5Mhz

  // ===============================================================
  // Leds
  // ===============================================================
  wire led1 = spi_ram_rd;
  wire led2 = spi_ram_wr;
  wire led3 = loading;
  wire led4 = !n_hard_reset;

  assign leds = {border_color, 1'b0 , led4, led3, led2, led1};
  
  always @(posedge clk) begin
    diag <= attrOut;
  end
   
endmodule

