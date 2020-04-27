# micropython ESP32
# ZX spectrum RAM snapshot image loader

# AUTHOR=EMARD
# LICENSE=BSD

# this code is SPI master to FPGA SPI slave
# FPGA sends pulse to GPIO after BTN state is changed.
# on GPIO pin interrupt from FPGA:
# btn_state = SPI_read
# SPI_write(buffer)
# FPGA SPI slave will accept image and start it

from machine import SPI, Pin, SDCard, Timer
from micropython import const, alloc_emergency_exception_buf
from uctypes import addressof
from struct import unpack
import os

import ecp5
import gc

class zx:
  def __init__(self):
    self.screen_x = const(64)
    self.screen_y = const(20)
    self.cwd = "/"
    self.init_fb()
    self.exp_names = " KMGTE"
    self.mark = bytearray([32,16,42]) # space, right triangle, asterisk
    self.read_dir()
    #self.spi_read_irq = bytearray([1,0xF1,0,0,0,0,0])
    self.spi_read_btn = bytearray([1,0xFB,0,0,0,0,0])
    self.spi_result = bytearray(7)
    self.spi_enable_osd = bytearray([0,0xFE,0,0,0,1])
    self.spi_write_osd = bytearray([0,0xFD,0,0,0])
    self.led = Pin(5, Pin.OUT)
    self.led.off()
    self.spi_channel = const(2)
    self.init_pinout_sd()
    self.spi_freq = const(4000000)
    self.hwspi=SPI(self.spi_channel, baudrate=self.spi_freq, polarity=0, phase=0, bits=8, firstbit=SPI.MSB, sck=Pin(self.gpio_sck), mosi=Pin(self.gpio_mosi), miso=Pin(self.gpio_miso))
    alloc_emergency_exception_buf(100)
    self.enable = bytearray(1)
    self.timer = Timer(3)
    self.irq_handler(0)
    self.irq_handler_ref = self.irq_handler # allocation happens here
    self.spi_request = Pin(0, Pin.IN, Pin.PULL_UP)
    self.spi_request.irq(trigger=Pin.IRQ_FALLING, handler=self.irq_handler_ref)
    self.rom="/sd/zxspectrum/roms/opense.rom"

# init file browser
  def init_fb(self):
    self.fb_topitem = 0
    self.fb_cursor = 0
    self.fb_selected = -1

  @micropython.viper
  def init_pinout_sd(self):
    self.gpio_sck  = const(16)
    self.gpio_mosi = const(4)
    self.gpio_miso = const(12)

  @micropython.viper
  def irq_handler(self, pin):
    p8result = ptr8(addressof(self.spi_result))
    self.led.on()
    self.hwspi.write_readinto(self.spi_read_btn, self.spi_result)
    self.led.off()
    btn_irq = p8result[6]
    if btn_irq&0x80: # btn event IRQ flag
      #self.led.on()
      #self.hwspi.write_readinto(self.spi_read_btn, self.spi_result)
      #self.led.off()
      btn = btn_irq&0x7F
      p8enable = ptr8(addressof(self.enable))
      if p8enable[0]&2: # wait to release all BTNs
        if btn==1:
          p8enable[0]&=1 # clear bit that waits for all BTNs released
      else: # all BTNs released
        if (btn&0x78)==0x78: # all cursor BTNs pressed at the same time
          self.show_dir() # refresh directory
          p8enable[0]=(p8enable[0]^1)|2;
          self.osd_enable(p8enable[0]&1)
        if p8enable[0]==1:
          if btn==9: # btn3 cursor up
            self.start_autorepeat(-1)
          if btn==17: # btn4 cursor down
            self.start_autorepeat(1)
          if btn==1:
            self.timer.deinit() # stop autorepeat
          if btn==33: # btn6 cursor left
            self.updir()
          if btn==65: # btn6 cursor right
            self.select_entry()

  def start_autorepeat(self, i:int):
    self.autorepeat_direction=i
    self.move_dir_cursor(i)
    self.timer_slow=1
    self.timer.init(mode=Timer.PERIODIC, period=500, callback=self.autorepeat)

  def autorepeat(self, timer):
    if self.timer_slow:
      self.timer_slow=0
      self.timer.init(mode=Timer.PERIODIC, period=30, callback=self.autorepeat)
    self.move_dir_cursor(self.autorepeat_direction)

  def select_entry(self):
    if self.direntries[self.fb_cursor][1]: # is it directory
      self.cwd = self.fullpath(self.direntries[self.fb_cursor][0])
      self.init_fb()
      self.read_dir()
      self.show_dir()
    else:
      self.change_file()

  def updir(self):
    if len(self.cwd) < 2:
      self.cwd = "/"
    else:
      s = self.cwd.split("/")[:-1]
      self.cwd = ""
      for name in s:
        if len(name) > 0:
          self.cwd += "/"+name
    self.init_fb()
    self.read_dir()
    self.show_dir()

  def fullpath(self,fname):
    if self.cwd.endswith("/"):
      return self.cwd+fname
    else:
      return self.cwd+"/"+fname

  def change_file(self):
    oldselected = self.fb_selected - self.fb_topitem
    self.fb_selected = self.fb_cursor
    try:
      filename = self.fullpath(self.direntries[self.fb_cursor][0])
    except:
      filename = False
      self.fb_selected = -1
    self.show_dir_line(oldselected)
    self.show_dir_line(self.fb_cursor - self.fb_topitem)
    if filename:
      self.loadz80(filename)
      self.osd_enable(0)
      self.enable[0]=0

  @micropython.viper
  def osd_enable(self, en:int):
    pena = ptr8(addressof(self.spi_enable_osd))
    pena[5] = en&1
    self.led.on()
    self.hwspi.write(self.spi_enable_osd)
    self.led.off()

  @micropython.viper
  def osd_print(self, x:int, y:int, i:int, text):
    p8msg=ptr8(addressof(self.spi_write_osd))
    a=0xF000+(x&63)+((y&31)<<6)
    p8msg[2]=i
    p8msg[3]=a>>8
    p8msg[4]=a
    self.led.on()
    self.hwspi.write(self.spi_write_osd)
    self.hwspi.write(text)
    self.led.off()

  @micropython.viper
  def osd_cls(self):
    p8msg=ptr8(addressof(self.spi_write_osd))
    p8msg[3]=0xF0
    p8msg[4]=0
    self.led.on()
    self.hwspi.write(self.spi_write_osd)
    self.hwspi.read(1280,32)
    self.led.off()

  # y is actual line on the screen
  def show_dir_line(self, y):
    if y < 0 or y >= self.screen_y:
      return
    mark = 0
    invert = 0
    if y == self.fb_cursor - self.fb_topitem:
      mark = 1
      invert = 1
    if y == self.fb_selected - self.fb_topitem:
      mark = 2
    i = y+self.fb_topitem
    if i >= len(self.direntries):
      self.osd_print(0,y,0,"%64s" % "")
      return
    if self.direntries[i][1]: # directory
      self.osd_print(0,y,invert,"%c%-57s     D" % (self.mark[mark],self.direntries[i][0]))
    else: # file
      mantissa = self.direntries[i][2]
      exponent = 0
      while mantissa >= 1024:
        mantissa >>= 10
        exponent += 1
      self.osd_print(0,y,invert,"%c%-57s %4d%c" % (self.mark[mark],self.direntries[i][0], mantissa, self.exp_names[exponent]))

  def show_dir(self):
    for i in range(self.screen_y):
      self.show_dir_line(i)

  def move_dir_cursor(self, step):
    oldcursor = self.fb_cursor
    if step == 1:
      if self.fb_cursor < len(self.direntries)-1:
        self.fb_cursor += 1
    if step == -1:
      if self.fb_cursor > 0:
        self.fb_cursor -= 1
    if oldcursor != self.fb_cursor:
      screen_line = self.fb_cursor - self.fb_topitem
      if screen_line >= 0 and screen_line < self.screen_y: # move cursor inside screen, no scroll
        self.show_dir_line(oldcursor - self.fb_topitem) # no highlight
        self.show_dir_line(screen_line) # highlight
      else: # scroll
        if screen_line < 0: # cursor going up
          screen_line = 0
          if self.fb_topitem > 0:
            self.fb_topitem -= 1
            self.show_dir()
        else: # cursor going down
          screen_line = self.screen_y-1
          if self.fb_topitem+self.screen_y < len(self.direntries):
            self.fb_topitem += 1
            self.show_dir()

  def read_dir(self):
    self.direntries = []
    ls = sorted(os.listdir(self.cwd))
    for fname in ls:
      stat = os.stat(self.fullpath(fname))
      if stat[0] & 0o170000 == 0o040000:
        self.direntries.append([fname,1,0]) # directory
      else:
        self.direntries.append([fname,0,stat[6]]) # file

  # LOAD/SAVE and CPU control

  # read from file -> write to SPI RAM
  def load_stream(self, filedata, addr=0, maxlen=0x10000, blocksize=1024):
    block = bytearray(blocksize)
    # Request load
    self.led.on()
    self.hwspi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    bytes_loaded = 0
    while bytes_loaded < maxlen:
      if filedata.readinto(block):
        self.hwspi.write(block)
        bytes_loaded += blocksize
      else:
        break
    self.led.off()

  # read from SPI RAM -> write to file
  def save_stream(self, filedata, addr=0, length=1024, blocksize=1024):
    bytes_saved = 0
    block = bytearray(blocksize)
    # Request save
    self.led.on()
    self.hwspi.write(bytearray([1,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0]))
    while bytes_saved < length:
      self.hwspi.readinto(block)
      filedata.write(block)
      bytes_saved += len(block)
    self.led.off()

  def ctrl(self,i):
    self.led.on()
    self.hwspi.write(bytearray([0, 0xFF, 0xFF, 0xFF, 0xFF, i]))
    self.led.off()

  def cpu_halt(self):
    self.ctrl(2)

  def cpu_continue(self):
    self.ctrl(0)

  def load_z80_compressed_stream(self, filedata, length=0xFFFF):
    b=bytearray(1)
    escbyte=bytearray([0xED])
    s=0
    repeat=0
    bytes_loaded=0
    while bytes_loaded < length:
      if filedata.readinto(b):
        nexts=s
        if s==0:
          if b[0]==escbyte[0]:
            nexts=1
          else:
            self.hwspi.write(b)
        if s==1:
          if b[0]==escbyte[0]:
            nexts=2
          else:
            self.hwspi.write(escbyte)
            self.hwspi.write(b)
            nexts=0
        if s==2:
          repeat=b[0]
          if repeat==0:
            print("end")
            break
          nexts=3
        if s==3:
          self.hwspi.read(repeat,b[0])
          nexts=0
        s=nexts
        bytes_loaded += 1
      else:
        break
    print("bytes loaded %d" % bytes_loaded)

  def load_z80_v1_compressed_block(self, filedata):
    self.led.on()
    self.hwspi.write(bytearray([0,0,0,0x40,0])) # from 0x4000
    self.load_z80_compressed_stream(filedata)
    self.led.off()

  def load_z80_v23_block(self, filedata):
    header = bytearray(3)
    if filedata.readinto(header):
      length,page = unpack("<HB",header)
      print("load z80 block: length=%d, page=%d" % (length,page))
    else:
      return False
    addr = -1
    if page==4:
      addr=0x8000
    if page==5:
      addr=0xC000
    if page==8:
      addr=0x4000
    if addr < 0:
      print("unsupported page ignored")
      filedata.seek(length,1)
      return True
    if length==0xFFFF:
      compress=0
      length=0x4000
    else:
      compress=1
    #print("addr=%04X compress=%d" % (addr,compress))
    if compress:
      # Request load
      self.led.on()
      self.hwspi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
      self.load_z80_compressed_stream(filedata,length)
      self.led.off()
    else:
      print("uncompressed v2/v3 may need FIXME")
      self.load_stream(filedata,addr,16384)
    return True
  
  def patch_rom(self,pc,header):
    # overwrite tape saving code in original ROM
    # with restore code and data from header
    code_addr = 0x4C2
    header_addr = 0x500
    self.led.on()
    self.hwspi.write(bytearray([0, 0,0,0,0, 0xF3, 0xAF, 0x11, 0xFF, 0xFF, 0xC3, code_addr&0xFF, (code_addr>>8)&0xFF])) # overwrite start of ROM to JP 0x04C2
    self.led.off()
    self.led.on()
    self.hwspi.write(bytearray([0, 0,0,(code_addr>>8)&0xFF,code_addr&0xFF])) # overwrite 0x04C2
    # Z80 code that POPs REGs from header as stack data at 0x500
    # z80asm restore.z80asm; hexdump -v -e '/1 "0x%02X,"' a.bin
    # restores border color, registers I, AFBCDEHL' and AFBCDEHL
    self.hwspi.write(bytearray([0x31,(header_addr+9)&0xFF,((header_addr+9)>>8)&0xFF,0xF1,0xED,0x47,0xF1,0x1F,0xD3,0xFE,0xD1,0xD9,0xC1,0xD1,0xE1,0xD9,0xF1,0x08,0xFD,0xE1,0xDD,0xE1,0x21,0xE5,0xFF,0x39,0xF9,0xF1,0xC1,0xE1]));
    self.hwspi.write(bytearray([0x31])) # LD SP, ...
    self.hwspi.write(header[8:10])
    self.hwspi.write(bytearray([0xED])) # IM ...
    imarg = bytearray([0x46,0x56,0x5E,0x5E])
    self.hwspi.write(bytearray([imarg[header[29]&3]])) # IM mode
    if header[27]:
      self.hwspi.write(bytearray([0xFB])) # EI
    header[6]=pc&0xFF
    header[7]=(pc>>8)&0xFF
    self.hwspi.write(bytearray([0xC3])) # JP ...
    self.hwspi.write(header[6:8]) # PC address of final JP
    self.led.off()
    self.led.on()
    self.hwspi.write(bytearray([0, 0,0,(header_addr>>8)&0xFF,header_addr&0xFF])) # overwrite 0x0500 with header
    # header fix: exchange A and F, A' and F' to become POPable
    x=header[0]
    header[0]=header[1]
    header[1]=x
    x=header[21]
    header[21]=header[22]
    header[22]=x
    if header[12]==255:
      header[12]=1
    #header[12] ^= 7<<1 # FIXME border color
    self.hwspi.write(header) # AF and AF' now POPable
    self.led.off()

  def loadz80(self,filename):
    z=open(filename,"rb")
    header1 = bytearray(30)
    z.readinto(header1)
    pc=unpack("<H",header1[6:8])[0]
    self.cpu_halt()
    self.load_stream(open(self.rom, "rb"), addr=0)
    if pc: # V1 format
      print("Z80 v1")
      self.patch_rom(pc,header1)
      if header1[12] & 32:
        self.load_z80_v1_compressed_block(z)
      else:
        self.load_stream(z,0x4000)
    else: # V2 or V3 format
      word = bytearray(2)
      z.readinto(word)
      length2 = unpack("<H", word)[0]
      if length2 == 23:
        print("Z80 v2")
      else:
        if length2 == 54 or length2 == 55:
          print("Z80 v3")
        else:
          print("unsupported header2 length %d" % length2)
          return
      header2 = bytearray(length2)
      z.readinto(header2)
      pc=unpack("<H",header2[0:2])[0]
      self.patch_rom(pc,header1)
      while self.load_z80_v23_block(z):
        pass
    z.close()
    self.ctrl(3) # reset and halt
    self.ctrl(1) # only reset
    self.cpu_continue()
    # restore original ROM after image starts
    self.cpu_halt()
    self.load_stream(open(self.rom, "rb"), addr=0)
    self.cpu_continue() # release reset


  # read from file -> write to SPI RAM
  def load_stream(self, filedata, addr=0, blocksize=1024):
    block = bytearray(blocksize)
    self.led.on()
    self.hwspi.write(bytearray([0x00, (addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    while True:
      if filedata.readinto(block):
        self.hwspi.write(block)
      else:
        break
    self.led.off()

  # NOTE: this can be used for debugging
  #def osd(self, a):
  #  if len(a) > 0:
  #    enable = 1
  #  else:
  #    enable = 0
  #  self.led.on()
  #  self.hwspi.write(bytearray([0,0xFE,0,0,0,enable])) # enable OSD
  #  self.led.off()
  #  if enable:
  #    self.led.on()
  #    self.hwspi.write(bytearray([0,0xFD,0,0,0])) # write content
  #    self.hwspi.write(bytearray(a)) # write content
  #    self.led.off()

def loadz80(filename):
  s=zx()
  s.loadz80(filename)

def load(filename, addr=0x4000):
  s=zx()
  s.cpu_halt()
  s.load_stream(open(filename, "rb"), addr=addr)
  s.cpu_continue()

def save(filename, addr=0x4000, length=0xC000):
  s=zx()
  f=open(filename, "wb")
  s.cpu_halt()
  s.save_stream(f, addr, length)
  s.cpu_continue()
  f.close()

def peek(addr,length=1):
  s=zx()
  s.cpu_halt()
  s.led.on()
  s.hwspi.write(bytearray([1,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0]))
  b=bytearray(length)
  s.hwspi.readinto(b)
  s.led.off()
  s.cpu_continue()
  return b

def poke(addr,data):
  s=zx()
  s.cpu_halt()
  s.led.on()
  s.hwspi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
  s.hwspi.write(data)
  s.led.off()
  s.cpu_continue()

os.mount(SDCard(slot=3),"/sd")
ecp5.prog("/sd/zxspectrum/bitstreams/zxspectrum12f.bit")
gc.collect()
spectrum=zx()
