LDFLAGS=-L$(HOME)/esp-open-sdk/xtensa-lx106-elf/xtensa-lx106-elf/sysroot/usr/lib -Teagle.app.v6.ld

all: forth.elf-0x00000.bin

forth.o: forth.S
	xtensa-lx106-elf-gcc -c -nostdlib forth.S -o forth.o
forth.elf: forth.o
	xtensa-lx106-elf-ld forth.o -o forth.elf $(LDFLAGS)

forth.elf-0x00000.bin: forth.elf
	esptool.py elf2image forth.elf

.PHONY: dump
dump: forth.elf
	xtensa-lx106-elf-objdump -EB -d -s forth.elf
