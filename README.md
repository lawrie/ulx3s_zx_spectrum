# ulx3s_zx_spectrum

Verilog ZX Spectrum 48k core for the Ulx3s ECP5 board.

Supports HDMI output and VGA output using a Digilent VGA Pmod.

Uses a PS/2 keyboard.

Games can be loaded in .z80 format from the ESP32.

Does not support models other than the Spectrum 16k and 48k.

To build and upload the bit file, do:


```sh
cd ulx3s
make prog
```

The default build is for the 85f. For other models, use the DEVICE parameter to the make file, e.g. `make DEVICE=12k`.

To set up the ESP32 follow the instructions at https://github.com/emard/esp32ecp5.

Upload the esp32/spiram.py and roms/48.rom files to the ESP32.

You can then upload a game from an SD card via the ESP32 by:

```python
import spiram, os
from machine import SDCard
os.mount(SDCard(slot=3),"/sd")
spiram.loadz80("/sd/mygame.z80") 
```

The game should then start immediately.
