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

from machine import SPI, Pin, SDCard
from micropython import const, alloc_emergency_exception_buf
#from uctypes import addressof
from struct import unpack
#from time import sleep_ms
import os

import ecp5
import gc

class zx:
  def __init__(self):
    alloc_emergency_exception_buf(100)
    self.spi_freq = const(4000000)
    self.spi_channel = const(2)
    self.init_pinout()
    self.init_spi()

  @micropython.viper
  def init_pinout(self):
    self.gpio_cs   = const(5)
    self.gpio_sck  = const(16)
    self.gpio_mosi = const(4)
    self.gpio_miso = const(12)

  def init_spi(self):
    self.spi=SPI(self.spi_channel, baudrate=self.spi_freq, polarity=0, phase=0, bits=8, firstbit=SPI.MSB, sck=Pin(self.gpio_sck), mosi=Pin(self.gpio_mosi), miso=Pin(self.gpio_miso))
    self.cs=Pin(self.gpio_cs, Pin.OUT)
    self.cs.off()


  def loadz80(self,filename):
    import ld_zxspectrum
    s=ld_zxspectrum.ld_zxspectrum(self.spi,self.cs)
    s.loadz80(filename)

  def load(self,filename, addr=0x4000):
    import ld_zxspectrum
    s=ld_zxspectrum.ld_zxspectrum(self.spi,self.cs)
    s.cpu_halt()
    s.load_stream(open(filename, "rb"), addr=addr)
    s.cpu_continue()

  def save(self,filename, addr=0x4000, length=0xC000):
    import ld_zxspectrum
    s=ld_zxspectrum.ld_zxspectrum(self.spi,self.cs)
    f=open(filename, "wb")
    s.cpu_halt()
    s.save_stream(f, addr, length)
    s.cpu_continue()
    f.close()

  def peek(self,addr,length=1):
    import ld_zxspectrum
    s=ld_zxspectrum.ld_zxspectrum(self.spi,self.cs)
    s.cpu_halt()
    s.cs.on()
    s.spi.write(bytearray([1,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0]))
    b=bytearray(length)
    s.spi.readinto(b)
    s.cs.off()
    s.cpu_continue()
    return b

  def poke(self,addr,data):
    import ld_zxspectrum
    s=ld_zxspectrum.ld_zxspectrum(self.spi,self.cs)
    s.cpu_halt()
    s.cs.on()
    s.spi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    s.spi.write(data)
    s.cs.off()
    s.cpu_continue()

def peek(addr,length=1):
  s=zx()
  return s.peek(addr,length)

def poke(addr,data):
  s=zx()
  s.peek(addr,data)

def loadz80(filename):
  s=zx()
  s.loadz80(filename)

def load(filename, addr=0x4000):
  s=zx()
  s.load(filename, addr)

def save(filename, addr=0x4000, length=0xC000):
  s=zx()
  s.save(filename,addr,length)
  
os.mount(SDCard(slot=3),"/sd")
ecp5.prog("/sd/zxspectrum/bitstreams/zxspectrum12f.bit")
gc.collect()
