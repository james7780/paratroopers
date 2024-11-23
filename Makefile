# Makefile for project built with lyxass
AS=../bin/x64/lyxass.exe
EMU=C:\Emulators\Mednafen\mednafen.exe

$(info BLL_ROOT is $(BLL_ROOT))

all: para.lnx

SRC = para.asm

para.lnx: $(SRC)
ifeq ($(BLL_ROOT),)
	$(warning Please set BLL_ROOT environmental variable first!)
else
	$(AS) -v -sh $(SRC)
	copy /b $(BLL_ROOT)\uloader\bll.enc + para.o para.lyx
	make_lnx para.lyx -b0 256K
	$(EMU) $@
endif

run: para.lnx
	$(EMU) para.lnx

clean:
	rm -f para.o
	rm -f para.lyx
	rm -f para.lnx
