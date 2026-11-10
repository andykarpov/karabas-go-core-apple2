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

Пользователь (2026-11-11): репозиторий `karabas-go-core-apple2` (создал сам, публичный).

Предложение (ждёт подтверждения; пока работаем по нему):

1. **Основа** — машина NanoApple2 / MiST (VHDL как есть в `src/rtl/`, правки для XST с пометкой `-- karabas:` / `// karabas:`, SV через sv2v). Исправления и карты MiSTer переносим отдельно (Ф5).
2. **Имя** `apple2` (`apple2.kg`, папка `/apple2`).
3. **Память.** RAM 64K main + 64K aux в SRAM (машине нужен 1 байт за такт 1 МГц — SRAM с запасом). Saturn 128K — туда же (Ф5). ПЗУ (системное 16K, видео 8K, клавиатуры 2K, Disk II, SSC, мыши, HDD) и буферы дорожек — BRAM. SDRAM не нужна.
4. **Видео** — развёртка NTSC с удвоением строк, как HDMI NanoApple2: 910 точек на строку на 28,636 МГц, 31,47 кГц, ~60 Гц, 524 строки; кадрового буфера нет. Клок 28,636 МГц = 50 · 63 / 110 (DCM_CLKGEN), машина на 14,318 МГц (CE). Проверить, что монитор пользователя принимает; запасной вариант — кадровый буфер в BRAM / SRAM и стандартный 720×480p / 640×480. Палитры (NTSC //e, IIgs, AppleWin), монохром (зелёный / янтарный / белый), скан-линии — из NanoApple2.
5. **Дискеты.** Сначала **.NIB** с записью (`floppy_track` → `img_sdc`, F-слоты 0 / 1). Затем **.DSK / .DO / .PO** — перевод в нибблы в ПЛИС при загрузке дорожки (6-and-2, только чтение, потом запись обратно). WOZ — позже, дорожка в SRAM.
6. **HDD** — `hdd.vhd` (ProDOS block device, слот 7), `.HDV` через `img_sdc`.
7. **Клавиатура, мышь, джойстик** — свой `apple2_hid.v` поверх `kg_mcu_hid`: HID-код → код клавиатуры //e (Open Apple = левый Alt, Closed Apple = Win), мышь → AppleMouse (слот 5), геймпад / мышь → аналоговый джойстик (пэддлы). Сброс — Menu+F12 (как в других ядрах), Ctrl+Reset — отдельная клавиша (F2 как в апстриме).
8. **Звук** — динамик + Mockingboard A (слот 4), на HDMI / PCM5102 / сигма-дельту.
9. **ПЗУ Apple** — ждёт решения: в репозитории и `.kg` (как в апстриме) или файл пользователя через `FL`.
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

## Фазы

Ветка и один PR на фазу, слияние в конце фазы.

- **Ф0. Импорт и fit.** `upstream/` (NanoApple2 без правок, ссылки на MiST / MiSTer), `src/rtl/` с правками XST, Gowin-примитивы → `kg_sprom` / `kg_sdpram` / `kg_tdpram`, sv2v для SV, Makefile, `core.json`, `make apple2-xst` (машина + карты). Готово, когда XST собирает без защёлок и ≥ 2× запаса по частоте.
- **Ф1. Симуляция.** Verilator (или GHDL + Verilator через XST-нетлист): машина + модель SRAM; загрузка ПЗУ до «Apple //e» и `]`, кадр в PNG; DOS 3.3 с `dos33master.nib` на модели `img_sdc`; клавиатура.
- **Ф2. Mini G.** Клоки, SRAM, видео с удвоением строк → HDMI со звуком, HID, OSD, ПЗУ, NIB A: / B:. Первый запуск на плате.
- **Ф3. Диски.** Запись NIB, смена диска, HDV в слоте 7, DSK / PO в нибблы.
- **Ф4. Карты.** Mockingboard, AppleMouse, джойстик / пэддлы, SSC (UART / Wi-Fi модем — по желанию).
- **Ф5. Go / Mini и релиз.** Верхи Go (VGA, PCM5102) и Mini, `cores.json`, README / GUIDE. Потом из MiSTer: Saturn 128K, No-Slot Clock (RTC платы), исправления видео / мыши, WOZ, Z80 SoftCard.

## Открытые вопросы

- База: NanoApple2 / MiST (предложено) или Verilog-машина MiSTer.
- Порядок форматов дискет: NIB → DSK (предложено) или сразу DSK.
- ПЗУ Apple в репозитории и `.kg` или файл пользователя.
- Примет ли монитор пользователя 910 × 524 @ 59,94 Гц (31,47 кГц).
