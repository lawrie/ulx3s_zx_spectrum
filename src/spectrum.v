`default_nettype none
module spectrum
#(
  parameter C_usb_speed=0,  // 0:6 MHz USB1.0, 1:48 MHz USB1.1, -1: USB disabled,
  // xbox360 : C_report_bytes=20, C_report_bytes_strict=1
  // darfon  : C_report_bytes= 8, C_report_bytes_strict=1
  parameter C_report_bytes=8, // 8:usual joystick, 20:xbox360
  parameter C_report_bytes_strict=1, // 0:when report length is variable/unknown
  parameter C_autofire_hz=10  // joystick trigger and bumper
)
(
  input         clk25_mhz,
  // Buttons
  input [6:0]   btn,
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
  output        wifi_gpio0,

  inout  sd_clk, sd_cmd,
  inout   [3:0] sd_d,

  inout  [27:0] gp,gn,
  // Leds
  output [7:0]  leds
);

  // VGA (should be assigned to some gp/gn outputs
  wire   [3:0]  red;
  wire   [3:0]  green;
  wire   [3:0]  blue;
  wire          hSync;
  wire          vSync;
  
  generate
    genvar i;
    for(i = 0; i < 4; i = i+1)
    begin
      assign gp[24-i-14] = red[i];
      assign gn[17-i-14] = green[i];
      assign gn[24-i-14] = blue[i];
    end
  endgenerate
  assign gp[16-14] = vSync;
  assign gp[17-14] = hSync;

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
  wire          n_joyCS;
  
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

  wire clk_125MHz, clk_25MHz; // video
  wire clk_48MHz, clk_6MHz; // usb
  wire dvi_clock_locked;
  clk_25_125_48_6_25
  clk_dvi_usb_inst
  (
    .clk25_i(clk25_mhz),
    .clk125_o(clk_125MHz),
    .clk48_o(clk_48MHz),
    .clk6_o(clk_6MHz),
    .clk25_o(clk_25MHz),
    .locked(dvi_clock_locked)
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
    //.clk(cpuClock), // turbo mode 28MHz
    .clk(cpuClockEnable), // normal mode 3.5MHz
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
  // USB joystick at US4 port
  // ===============================================================

  wire clk_usb;  // 6 MHz USB1.0 or 48 MHz USB1.1
  generate if (C_usb_speed == 0) begin: G_low_speed
      assign clk_usb = clk_6MHz;
  end
  endgenerate
  generate if (C_usb_speed == 1) begin: G_full_speed
      assign clk_usb = clk_48MHz;
  end
  endgenerate

  assign gp[22] = 1'b0; // pull down
  assign gn[22] = 1'b0; // pull down
  wire [C_report_bytes*8-1:0] S_report;
  wire S_report_valid;
  wire [7:0] usb_buttons;
  generate if (C_usb_speed >= 0) begin
  usbh_host_hid
  #(
    .C_usb_speed(C_usb_speed), // '0':Low-speed '1':Full-speed
    .C_report_length(C_report_bytes),
    .C_report_length_strict(C_report_bytes_strict)
  )
  us4_hid_host_inst
  (
    .clk(clk_usb), // 6 MHz for low-speed USB1.0 device or 48 MHz for full-speed USB1.1 device
    .bus_reset(~dvi_clock_locked),
    .led(), // debug output
    .usb_dif(gp[20]),
    .usb_dp(gp[24]),
    .usb_dn(gn[24]),
    .hid_report(S_report),
    .hid_valid(S_report_valid)
  );
  end
  endgenerate

  usbh_report_decoder
  #(
    .c_autofire_hz(C_autofire_hz)
  )
  usbh_report_decoder_inst
  (
    .i_clk(clk_usb),
    .i_report(S_report),
    .i_report_valid(S_report_valid),
    .o_btn(usb_buttons)
  );

  wire [6:0] R_btn_joy;
  always @(posedge cpuClock)
    R_btn_joy <= btn | { usb_buttons[7],usb_buttons[6],usb_buttons[5],usb_buttons[4],usb_buttons[0],usb_buttons[1],1'b0};

  // ===============================================================
  // SPI Slave
  // ===============================================================
 
  wire spi_ram_wr, spi_ram_rd;
  wire [31:0] spi_ram_addr;
  wire [7:0] spi_ram_di;
  wire [7:0] ramOut;
  wire [7:0] spi_ram_do = ramOut;

  assign sd_d[3] = 1'bz; // FPGA pin pullup sets SD card inactive at SPI bus

  wire irq;
  spi_ram_btn
  #(
    .c_sclk_capable_pin(1'b0),
    .c_addr_bits(32)
  )
  spi_ram_btn_inst
  (
    .clk(cpuClock),
    .csn(~wifi_gpio5),
    .sclk(wifi_gpio16),
    .mosi(sd_d[1]), // wifi_gpio4
    .miso(sd_d[2]), // wifi_gpio12
    .btn(R_btn_joy),
    .irq(irq),
    .wr(spi_ram_wr),
    .rd(spi_ram_rd),
    .addr(spi_ram_addr),
    .data_in(spi_ram_do),
    .data_out(spi_ram_di)
  );
  assign wifi_gpio0 = ~irq;

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

  wire [7:0] osd_vga_r, osd_vga_g, osd_vga_b;
  wire osd_vga_hsync, osd_vga_vsync, osd_vga_blank;
  spi_osd
  #(
    .c_start_x(62), .c_start_y(80),
    .c_chars_x(64), .c_chars_y(20),
    .c_init_on(0),
    .c_char_file("osd.mem"),
    .c_font_file("font_bizcat8x16.mem")
  )
  spi_osd_inst
  (
    .clk_pixel(clk_vga), .clk_pixel_ena(1),
    .i_r({red,   {4{red[0]}}   }),
    .i_g({green, {4{green[0]}} }),
    .i_b({blue,  {4{blue[0]}}  }),
    .i_hsync(~hSync), .i_vsync(~vSync), .i_blank(~vga_de),
    .i_csn(~wifi_gpio5), .i_sclk(wifi_gpio16), .i_mosi(sd_d[1]), // .o_miso(),
    .o_r(osd_vga_r), .o_g(osd_vga_g), .o_b(osd_vga_b),
    .o_hsync(osd_vga_hsync), .o_vsync(osd_vga_vsync), .o_blank(osd_vga_blank)
  );

  // Convert VGA to HDMI
  HDMI_out vga2dvid (
    .pixclk(clk_vga),
    .pixclk_x5(clk_hdmi),
    .red  (osd_vga_r),
    .green(osd_vga_g),
    .blue (osd_vga_b),
    .vde(~osd_vga_blank),
    .hSync(osd_vga_hsync),
    .vSync(osd_vga_vsync),
    .gpdi_dp(gpdi_dp),
    .gpdi_dn(gpdi_dn)
  );

  // ===============================================================
  // SPI IRQ
  // ===============================================================

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

  assign n_kbdCS = cpuAddress[7:0] == 8'HFE && n_ioRD == 1'b0 ? 1'b0 : 1'b1;
  assign n_joyCS = cpuAddress[7:0] == 8'd31 && n_ioRD == 1'b0 ? 1'b0 : 1'b1; // kempston joystick
  assign n_romCS = cpuAddress[15:14] != 0;
  assign n_ramCS = !n_romCS;

  // ===============================================================
  // Memory decoding
  // ===============================================================

  assign cpuDataIn =  n_kbdCS == 1'b0 ? {3'b111, key_data} :
                      n_joyCS == 1'b0 ? {2'b0, R_btn_joy[2], R_btn_joy[1], R_btn_joy[3], R_btn_joy[4], R_btn_joy[5], R_btn_joy[6]} : // x x (x or FIRE2 on modified hardware) FIRE1 UP DOWN LEFT RIGHT
                      ramOut;

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

  assign leds = {border_color, irq , led4, led3, led2, led1};
  
endmodule
