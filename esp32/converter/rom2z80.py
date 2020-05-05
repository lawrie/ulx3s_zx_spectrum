#!/usr/bin/env python3

# convert raw code from a file to orao snapshot

import struct
code=open("../../roms/opense.rom","rb").read()
addr=0xC000
f = open("rom.z80","wb")
header1 = bytearray(30)
header2 = bytearray(23)
header3 = bytearray(3)
pc=0
header2[0:2] = struct.pack("<H",pc)
header3 = struct.pack("<HB",0xFFFF,0) # 16K uncompressed, page 0 (ROM)
f.write(header1)
f.write(struct.pack("<H",len(header2)))
f.write(header2)
f.write(header3)
f.write(code)
f.close()
