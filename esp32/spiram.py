# micropython ESP32
# SPI RAM test R/W

# AUTHOR=EMARD
# LICENSE=BSD

# this code is SPI master to FPGA SPI slave

# FIXME: *.z80 format unpacking
# https://www.worldofspectrum.org/faq/reference/z80format.htm

from machine import SPI, Pin
from micropython import const
from struct import unpack
from uctypes import addressof

class spiram:
  def __init__(self):
    self.led = Pin(5, Pin.OUT)
    self.led.off()
    self.spi_channel = const(1)
    self.init_pinout_sd()
    self.spi_freq = const(2000000)
    self.hwspi=SPI(self.spi_channel, baudrate=self.spi_freq, polarity=0, phase=0, bits=8, firstbit=SPI.MSB, sck=Pin(self.gpio_sck), mosi=Pin(self.gpio_mosi), miso=Pin(self.gpio_miso))

  @micropython.viper
  def init_pinout_sd(self):
    self.gpio_sck  = const(16)
    self.gpio_mosi = const(4)
    self.gpio_miso = const(12)

  # read from file -> write to SPI RAM
  def load_stream(self, filedata, addr=0, blocksize=1024):
    block = bytearray(blocksize)
    # Request load
    self.led.on()
    self.hwspi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    while True:
      if filedata.readinto(block):
        self.hwspi.write(block)
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

  def cpu_halt(self):
    self.led.on()
    self.hwspi.write(bytearray([0, 0xFF, 0xFF, 0xFF, 0xFF, 2]))
    self.led.off()

  def cpu_continue(self):
    self.led.on()
    self.hwspi.write(bytearray([0, 0xFF, 0xFF, 0xFF, 0xFF, 0]))
    self.led.off()

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
    self.hwspi.write(bytearray([0,0,0,0,0]))
    self.load_z80_compressed_stream(filedata)
    self.led.off()

  def load_z80_v23_block(self, filedata):
    header = bytearray(3)
    if filedata.readinto(header):
      length,page = unpack("<HB",header)
      print("load z80 block: length=%d, page=%d" % (length,page))
    else:
      return False
    addr = 0
    if page==4:
      addr=0x8000
    if page==5:
      addr=0xC000
    if page==8:
      addr=0x4000
    if length==0xFFFF:
      compress=0
      length=0x4000
    else:
      compress=1
    print("addr=%04X compress=%d" % (addr,compress))
    if compress:
      # Request load
      self.led.on()
      addr-=0x4000
      self.hwspi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
      self.load_z80_compressed_stream(filedata,length)
      self.led.off()
    else:
      self.load_stream(filedata,addr)
    return True

def loadz80(filename):
  s=spiram()
  z=open(filename,"rb")
  header1 = bytearray(30)
  z.readinto(header1)
  pc=unpack("<H",header1[6:8])[0]
  if pc:
    print("Z80 v1")
    print("PC=0x%04X PRINT USR %d" % (pc,pc))
    if header1[12] & 32:
      s.cpu_halt()
      s.load_z80_v1_compressed_block(z)
      s.cpu_continue()
      return
    else:
      s.cpu_halt()
      s.load_stream(z)
      s.cpu_continue()
  else:
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
  print("PC=0x%04X" % pc)
  s.cpu_halt()
  while s.load_z80_v23_block(z):
    pass
  s.cpu_continue()

def load(filename, addr=0x4000):
  s=spiram()
  addr -= 0x4000
  s.cpu_halt()
  s.load_stream(open(filename, "rb"), addr=addr)
  s.cpu_continue()

def save(filename, addr=0x4000, length=0xC000):
  s=spiram()
  addr -= 0x4000
  f=open(filename, "wb")
  s.cpu_halt()
  s.save_stream(f, addr, length)
  s.cpu_continue()
  f.close()

def ctrl(i):
  s=spiram()
  s.led.on()
  s.hwspi.write(bytearray([0, 0xFF, 0xFF, 0xFF, 0xFF, i]))
  s.led.off()
  
def peek(addr,length=1):
  s=spiram()
  s.cpu_halt()
  s.led.on()
  addr -= 0x4000
  s.hwspi.write(bytearray([1,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0]))
  b=bytearray(length)
  s.hwspi.readinto(b)
  s.led.off()
  s.cpu_continue()
  print(b)

def poke(addr,data):
  s=spiram()
  s.cpu_halt()
  s.led.on()
  addr -= 0x4000
  s.hwspi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
  s.hwspi.write(data)
  s.led.off()
  s.cpu_continue()

def help():
  print("spiram.load(\"file.bin\",addr=0)")
  print("spiram.save(\"file.bin\",addr=0,length=1024)")

