# Apple //e core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

An Apple //e (enhanced) for the Karabas Go family of boards (Xilinx Spartan-6 XC6SLX25): a port of
the MiST core [apple2efpga](https://github.com/gyurco/apple2efpga) as extended by
[NanoApple2](https://github.com/MiSTle-Dev/NanoApple2). All file work (disk and hard disk images)
goes through the OSD and the file browser of the board firmware: the core has no loader of its own.
A user guide (Russian) is in `docs/GUIDE.md`, the plan and the decisions in `docs/PLAN.md` (Russian).

| Board | Core file | Video | Audio | State |
|---|---|---|---|---|
| Karabas Mini G | `apple2.kg` | HDMI, 640x480 60 Hz | HDMI, I2S DAC (PCM5102) | tested on hardware |
| Karabas Mini | `apple2.kg` | HDMI, as Mini G | HDMI, analog output (sigma-delta) | built, not tested on hardware |
| Karabas Go | `apple2.kg` | VGA, as Mini G | I2S DAC (PCM5102) | built, not tested on hardware |

The core file is `src/apple2.kg`, one file for all three boards, with the Apple ROMs built in. It
needs the firmware v26110415 or later. The OSD items look for files in `/apple2` on the SD card.

## What it does

- **The machine:** Apple //e enhanced, 65C02 (or 6502, the OSD item CPU) at 1.02 MHz, 64 KB main +
  64 KB aux RAM (in the SRAM of the board), 80 columns, lo-res / hi-res / double hi-res, the
  speaker.
- **Disk II (slot 6), two drives:** `.nib`, and the 140 KB sector images `.dsk` / `.do` / `.po`
  (DOS or ProDOS order, found from the volume directory, not from the extension), read and write:
  writes go back to the image file. A read only file is a write protected disk. A new image can be
  chosen while the machine runs.
- **Hard disk (slot 7):** a ProDOS block image (`.hdv`, `.po`), read and write.
- **Mockingboard (slot 4):** two AY-3-8910 with their 6522s, stereo.
- **AppleMouse (slot 5):** the USB mouse, for the programs that use the card.
- **Super Serial Card (slot 2):** the OSD item Serial: on the USB serial port of the board (the
  speed set by the Apple goes to the port) or on the Wi-Fi module of the board (ESP8266 AT
  firmware, 115200).
- **Joystick:** the joystick of the board or a USB gamepad as the two paddles 0 / 1 and buttons 0 / 1.
- **Video:** the 560 x 192 picture of the //e in a 640 x 480 frame, colour (NTSC artefact colours,
  four palettes) or a monochrome monitor (white, green, amber).

Checked on the Mini G: DOS 3.3 and ProDOS 2.4 from `.nib` / `.dsk` / `.po`, `SAVE` on the floppy
images and on the hard disk (the files are there after the image is mounted again), the change of a
disk, the Mockingboard (tones and stereo), the paddles and buttons, the mouse, the serial card on
the USB port (both ways) and on the ESP module (`AT`, `AT+GMR`, `AT+CWLAP` from the terminal of the
card). Not there: WOZ images, the Saturn 128K card, a clock card, the Z80 SoftCard.

## OSD

The OSD opens with Menu+Esc ("Menu" is the Windows key).

| Item | What it does | Hotkey |
|---|---|---|
| Disk 1, Disk 2 | the image of drive 1 / 2 of slot 6 (`.nib`, `.dsk`, `.do`, `.po`) | Menu+F1, Menu+F2 |
| Hard disk | the ProDOS image of slot 7 (`.hdv`, `.po`) | Menu+F3 |
| CPU | 65C02 (the enhanced //e) or 6502 | |
| Monitor | Color, B&W, Green, Amber | Menu+M |
| Palette | the colours: NTSC, IIgs, AppleWin, Custom | |
| Mockingbrd | the Mockingboard in slot 4 on / off | |
| Mouse | the AppleMouse in slot 5 on / off | |
| Serial | the Super Serial Card in slot 2: Off, USB UART, ESP Wi-Fi | |
| ESP bit 7 | (ESP Wi-Fi only) Clear: the bytes go to the module with bit 7 = 0; Keep: 8 bit clean | |
| Reset | a power on reset: the //e boots from drive 1 | F12 |

## Keys

| PC key | Apple //e |
|---|---|
| Ctrl+Pause | Ctrl+Reset (a warm reset: the program stays) |
| left Windows | Open Apple |
| Alt | Closed Apple (Solid Apple) |
| F12 | Reset of the OSD: a cold start, the //e boots the disk |

## Licence

NanoApple2 and apple2efpga are GPL v3; the Karabas parts are GPL v3 (`LICENSE`). The Apple ROMs in
`src/roms` are Apple's.
