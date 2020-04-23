# micropython ESP32
# SPI RAM test R/W

# AUTHOR=EMARD
# LICENSE=BSD

# this code is SPI master to FPGA SPI slave

from machine import SPI, Pin
from micropython import const

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
    self.led.on()
    # Halt the CPU
    self.hwspi.write(bytearray([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x02]))
    self.led.off()
    # Request load
    self.led.on()
    self.hwspi.write(bytearray([0x00,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    while True:
      if filedata.readinto(block):
        self.hwspi.write(block)
      else:
        break
    # Restart the CPU
    self.led.off()
    self.led.on()
    self.hwspi.write(bytearray([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]))
    self.led.off()

  # read from SPI RAM -> write to file
  def save_stream(self, filedata, addr=0, length=1024, blocksize=1024):
    bytes_saved = 0
    block = bytearray(blocksize)
    self.led.on()
    # Halt the CPU
    self.hwspi.write(bytearray([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x02]))
    self.led.off()
    # Request save
    self.led.on()
    self.hwspi.write(bytearray([0x01,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0x00]))
    while bytes_saved < length:
      self.hwspi.readinto(block)
      filedata.write(block)
      bytes_saved += len(block)
    self.led.off()
    self.led.on()
    # Restart the CPU
    self.hwspi.write(bytearray([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]))
    self.led.off()

def load(filename, addr=0x4000):
  s=spiram()
  addr -= 0x4000
  s.load_stream(open(filename, "rb"), addr)

def save(filename, addr=0x4000, length=0xC000):
  s=spiram()
  addr -= 0x4000
  f=open(filename, "wb")
  s.save_stream(f, addr, length)
  f.close()

def ctrl(i):
  s=spiram()
  s.led.on()
  s.hwspi.write(bytearray([0x00, 0xFF, 0xFF, 0xFF, 0xFF, i]))
  s.led.off()
  
def peek(addr,length):
  s=spiram()
  s.led.on()
  addr -= 0x4000
  s.hwspi.write(bytearray([0x01,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0x00]))
  b=bytearray(length)
  s.hwspi.readinto(b)
  s.led.off()
  print(b)

def poke(addr,data):
  s=spiram()
  s.led.on()
  addr -= 0x4000
  s.hwspi.write(bytearray([0x00,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
  s.hwspi.write(data)
  s.led.off()

def help():
  print("spiram.load(\"file.bin\",addr=0)")
  print("spiram.save(\"file.bin\",addr=0,length=1024)")

