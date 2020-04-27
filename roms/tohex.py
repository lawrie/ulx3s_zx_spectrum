with open("opense.rom", "rb") as f:
    byte = f.read(1)
    while byte != b"":
        print("".join("%02x" % ord(byte)))
        byte = f.read(1)
