# План ядра Apple IIe для Karabas Go / Mini / Mini G

Цель: Apple //e enhanced (65C02 / 6502, 64 КБ + 64 КБ aux, 80 колонок, double hi-res) на платах Karabas (XC6SLX25, ISE 14.7). Основа — машина MiST [apple2efpga](https://github.com/gyurco/apple2efpga) в виде, доведённом [NanoApple2](https://github.com/MiSTle-Dev/NanoApple2) (запись NIB, HDD, Mockingboard, AppleMouse, SSC). Из [Apple-II_MiSTer](https://github.com/MiSTer-devel/Apple-II_MiSTer) берём потом отдельные части. Файлы идут через прошивку (OSD, `FL`, `F`, `img_sdc`): загрузчика и soft-CPU в ядре нет. Репозиторий `andykarpov/karabas-go-core-apple2`, публичный.

## Что изучено (2026-11-11)

| Проект | Состояние | Что внутри |
|---|---|---|
| [MiSTle-Dev/NanoApple2](https://github.com/MiSTle-Dev/NanoApple2) 4977e04 (2026-03-21), GPL v3 | живой, платы Tang (GW2A / GW5A) | машина MiST на VHDL (`apple2.vhd`, R65C02 + T65, `video_generator`, `timing_generator`), обвязка MiSTeryNano (sysctrl / sd_card через SPI µC — как в atarist). RAM 64K + 64K в SDRAM. Клоки 14,318 / 28,6 / HDMI ×5. Дискеты **.NIB чтение и запись** (`floppy_track.sv`: дорожка 6656 байт = 13 секторов в BRAM на привод, `disk_ii.vhd`), HDD **.HDV** (`hdd.vhd`, слот 7), Mockingboard A (`via6522.vhd` + jt49), AppleMouse (jt6805 + `pia6821`), SSC (`uart_6551`, Wi-Fi модем), language card. DSK не поддерживает. Примитивы Gowin (prom, sdpb, dpb, pll) — заменить |
| [gyurco/apple2efpga](https://github.com/gyurco/apple2efpga) 518f05f (2025-03-14) | MiST / SiDi / Poseidon | родитель NanoApple2, весь VHDL; IDE CFFA в слоте 7; `T65` — подмодуль (в NanoApple2 копия). У `apple2.vhd` нет заголовка лицензии (Edwards / Szombathelyi) |
| [MiSTer-devel/Apple-II_MiSTer](https://github.com/MiSTer-devel/Apple-II_MiSTer) c701e64 (2026-10-15) | живой | машина переписана на Verilog (`apple2.v`, `apple2_top.v`), новые 65C02 на SV; WOZ с записью (32 КБ BRAM на привод); DSK / DO / PO / NIB переводит в WOZ MiSTer Main на HPS (у нас нет); save states (DDR), Saturn 128K, No-Slot Clock, Z80 SoftCard (T80), композитный NTSC-декодер, экранная клавиатура. Вся RAM (256 КБ) в BRAM |

### Проба XST (xc6slx25-2, блоки MiST по отдельности, `-iobuf NO`)

| Блок | LUT | FF | RAMB | Fmax |
|---|---|---|---|---|
| `apple2` (оба CPU, видео) | 1507 | 348 | 4 (+ ~11 под ПЗУ: без содержимого XST их выкинул) | 54,9 МГц |
| `disk_ii` | 274 | 112 | 1 | 138 МГц |
| `MOCKINGBOARD` MiSTer (YM2149 через sv2v) | 1372 | 854 | 0 | 135 МГц |

Мышь, SSC, HDD, видеоконтроллер и обвязка платы (HDMI, OSD, MCU) не синтезировались. Оценка: **около 8–10K LUT из 15K** — помещается на все платы с запасом.

Правки, без которых XST не собирает:
- `x : work.spram` без `entity` (`video_generator.vhd`, `apple2.vhd`);
- компонент `vol_table` без объявления в `YM2149.vhd` MiST (берём jt49 NanoApple2 или YM2149 MiSTer);
- агрегаты на портах Verilog-модулей в `mockingboard.vhd` NanoApple2 — через промежуточные сигналы;
- `jt6805_ctrl.v`: сигналы используются до объявления;
- `gen_uart.v`: объявления в безымянном блоке.

## Решения

Пользователь (2026-11-11): репозиторий `karabas-go-core-apple2` (создал сам, публичный). Подтвердил: основа NanoApple2 / MiST (п. 1), ПЗУ в репозитории и `.kg` (п. 9), дискеты сначала NIB, потом DSK / PO (п. 5). Видео — **сразу кадровый буфер** и стандартная развёртка 640×480 / 720×480p (п. 4 изменён).

Решения:

1. **Основа** — машина NanoApple2 / MiST (VHDL как есть в `src/rtl/`, правки для XST с пометкой `-- karabas:` / `// karabas:`, SV через sv2v). Исправления и карты MiSTer переносим отдельно (Ф5).
2. **Имя** `apple2` (`apple2.kg`, папка `/apple2`).
3. **Память.** RAM 64K main + 64K aux в SRAM (машине нужен 1 байт за такт 1 МГц — SRAM с запасом). Saturn 128K — туда же (Ф5). ПЗУ (системное 16K, видео 8K, клавиатуры 2K, Disk II, SSC, мыши, HDD) и буферы дорожек — BRAM. SDRAM не нужна.
4. **Видео** — кадровый буфер и стандартная развёртка 640×480@60 (или 720×480p), решение пользователя 2026-11-11. Кадр Apple 560×192 (точки double hi-res) → 560×384 с удвоением строк в окне 640×480. Буфер в SRAM рядом с RAM машины (4 бита на точку = 54 КБ; BRAM на него не хватит: ПЗУ и буферы дорожек уже ~22 RAMB16 из 52), чтение строками в BRAM-буфер строки. Цвет NTSC (artifact colour) считается при записи в буфер, как `vga_controller` делает сейчас. Детали — в Ф2. Палитры (NTSC //e, IIgs, AppleWin), монохром (зелёный / янтарный / белый) — из NanoApple2.
5. **Дискеты.** Сначала **.NIB** с записью (`floppy_track` → `img_sdc`, F-слоты 0 / 1). Затем **.DSK / .DO / .PO** — перевод в нибблы в ПЛИС при загрузке дорожки (6-and-2, только чтение, потом запись обратно). WOZ — позже, дорожка в SRAM.
6. **HDD** — `hdd.vhd` (ProDOS block device, слот 7), `.HDV` через `img_sdc`.
7. **Клавиатура, мышь, джойстик** — свой `apple2_hid.v` поверх `kg_mcu_hid`: HID-код → код клавиатуры //e (Open Apple = левый Alt, Closed Apple = Win), мышь → AppleMouse (слот 5), геймпад / мышь → аналоговый джойстик (пэддлы). Сброс — Menu+F12 (как в других ядрах), Ctrl+Reset — отдельная клавиша (F2 как в апстриме).
8. **Звук** — динамик + Mockingboard A (слот 4), на HDMI / PCM5102 / сигма-дельту.
9. **ПЗУ Apple** — в репозитории и `.kg`, как в апстриме (`src/roms/*.mi` → `.hex` для `kg_sprom`).
10. **Свой верх платы**, общий код через `modules` (`kg_mcu`, `img_sdc`, OSD, HDMI, PCM5102), Makefile как у atarist / archie. Первым — Mini G, затем Go и Mini. Mini G2: T3 = 0 (SDRAM ~CS). Физический дисковод Go не подходит (Disk II — не Shugart): выходы `FDC_*` = 0.

## Архитектура

```
 apple2 (MiST VHDL) ├── 6502 / 65C02 ── ram_addr / D / ram_we ── apple2_sram ── SRAM: main 64K, aux 64K (+ Saturn)
                    ├── ПЗУ 16K, видео 8K ── BRAM
                    ├── video_generator ── vga_controller (удвоение строк, палитра) ── OSD ── HDMI / VGA
                    ├── динамик ─┬──────────────────────────────────── HDMI / PCM5102 / сигма-дельта
 слот 4 Mockingboard ────────────┘
 слот 5 AppleMouse ─┐
 клавиатура / пэддлы┴── apple2_hid ── kg_mcu HID
 слот 6 disk_ii ── floppy_track ×2 (BRAM-буфер дорожки) ──┐
 слот 7 hdd ── буфер сектора ─────────────────────────────┴── img_sdc ── kg_mcu (file mounter)
 слот 2 SSC ── uart_6551 ── UART / ESP (модем, позже)
```

## Итоги Ф0 (2026-11-11)

`make apple2-xst` (машина со всеми картами, `src/rtl/karabas/apple2_top.vhd`, `-iobuf NO`): **4858 LUT (32 %), 2259 FF, 30 RAMB16 из 52, 2 DSP48**, защёлок нет; `clk_core` 51,3 МГц (нужно 14,3), `clk_sys` 126,5 МГц (нужно 28,6).

- Память Gowin → `src/rtl/karabas/gowin_mem.v`: те же имена модулей поверх `kg_sprom` / `kg_sdpram` / `kg_tdpram` / `kg_spram`, ПЗУ из `src/roms/*.hex` (`tools/mi2hex.py`).
- Микрокод jt6805 (мышь, 4096 × 39 бит = 10 RAMB16) — всего 145 разных слов: индекс 4096 × 8 в BRAM + таблица слов в LUT (`tools/uc_compress.py`), 2 RAMB16, +100 LUT. Содержимое сверено с Gowin-ПЗУ апстрима.
- BRAM: ПЗУ 16K — 8, видео-ПЗУ 8K — 4, буферы дорожек 2 × 8K — 8, микрокод — 2, ПЗУ мыши / SSC / клавиатуры — 4, остальное (Disk II, HDD, сектор, опкоды R65C02, RAM 6805) — 4. Под OSD и буферы строк кадрового буфера остаётся ~22.
- Правки XST в апстриме (`karabas:`): битовые строки VHDL-2008 (`7X".."`, `10x".."`), `others` в `case`, без преобразования типа на формальных портах Verilog-модулей, без агрегатов на портах jt49, объявления до `include` в `jt6805_ctrl.v`, `start_d` / `rx_filtered` в `gen_uart.v`, двойной драйвер `tstop` в `jtframe_6805mcu.v`; `floppy_track.sv` и `uart_6551.v` через sv2v (`tools/sv2v.sh`).
- Исправление апстрима: `IO_STROBE` ($C800–$CFFF) не выходил из `apple2.vhd` и не был подключён в верхе NanoApple2 — у SSC не работало ПЗУ $C800. Теперь порт.
- Проверить в Ф1: XST обрезал `ca*_fall` в `pia6821` мыши (константа 0) — посмотреть, правильно ли подключены входы PIA.

## Итоги Ф1 (2026-11-11)

Модель Verilator: `src/sim/run_boot.sh` (VHDL → Verilog через `ghdl --synth`, `sim/vhdl2v.sh`; Verilog-модули — чёрные ящики, `sim/bb_comp.py`), стенд `sim/tb_apple2.v` (RAM 64K + 64K) + `sim/sim_apple2.cpp` (тактовые, SD с образами, ввод текста, кадры PPM). Скорость ~35 мс машинного времени в секунду.

- После сброса по питанию (0,3 с) — «Apple //e», ПЗУ ищет диск в слоте 6; с `dos33master.nib` головка уходит на дорожку 0 и грузятся дорожки 0–2 (к 3 с). До `]` (~7 с, ~4 мин счёта) не гоняли — по решению пользователя проверка дальше на плате.
- **Найдено: чтение RAM должно быть регистровым на 14 МГц.** CPU берёт `ram_do` на такте после спада `PHASE_ZERO`, когда `ram_addr` уже адрес видео; SDRAM MiST / NanoApple2 держала данные. С асинхронной RAM CPU читает мусор (уходит в BRK). `apple2_sram` на плате — так же: `dout <= SRAM[addr]` каждый такт `clk_core`.

## Фазы

Ветка и один PR на фазу, слияние в конце фазы.

- **Ф0. Импорт и fit.** `upstream/` (NanoApple2 без правок, ссылки на MiST / MiSTer), `src/rtl/` с правками XST, Gowin-примитивы → `kg_sprom` / `kg_sdpram` / `kg_tdpram`, sv2v для SV, Makefile, `core.json`, `make apple2-xst` (машина + карты). Готово, когда XST собирает без защёлок и ≥ 2× запаса по частоте.
- **Ф1. Симуляция.** Verilator (или GHDL + Verilator через XST-нетлист): машина + модель SRAM; загрузка ПЗУ до «Apple //e» и `]`, кадр в PNG; DOS 3.3 с `dos33master.nib` на модели `img_sdc`; клавиатура.
- **Ф2. Mini G.** Клоки, SRAM, видео с удвоением строк → HDMI со звуком, HID, OSD, ПЗУ, NIB A: / B:. Первый запуск на плате.
- **Ф3. Диски.** Запись NIB, смена диска, HDV в слоте 7, DSK / PO в нибблы.
- **Ф4. Карты.** Mockingboard, AppleMouse, джойстик / пэддлы, SSC (UART / Wi-Fi модем — по желанию).
- **Ф5. Go / Mini и релиз.** Верхи Go (VGA, PCM5102) и Mini, `cores.json`, README / GUIDE. Потом из MiSTer: Saturn 128K, No-Slot Clock (RTC платы), исправления видео / мыши, WOZ, Z80 SoftCard.

## Открытые вопросы

- Нет (2026-11-11). Новые — сюда.
