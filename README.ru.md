# Ядро Apple //e для Karabas Go / Mini / Mini G

[English version](README.md)

Apple //e (enhanced) для плат семейства Karabas Go (Xilinx Spartan-6 XC6SLX25): порт ядра MiST
[apple2efpga](https://github.com/gyurco/apple2efpga) в версии
[NanoApple2](https://github.com/MiSTle-Dev/NanoApple2). Вся работа с файлами (образы дискет и
жёсткого диска) идёт через OSD и файловый браузер прошивки платы: своего загрузчика в ядре нет.
Руководство пользователя — `docs/GUIDE.md`, план и решения — `docs/PLAN.md`.

| Плата | Файл ядра | Видео | Звук | Состояние |
|---|---|---|---|---|
| Karabas Mini G | `apple2.kg` | HDMI, 640x480 60 Гц | HDMI, I2S ЦАП (PCM5102) | проверено на плате |
| Karabas Mini | `apple2.kg` | HDMI, как Mini G | HDMI, аналоговый выход (сигма-дельта) | собрано, на плате не проверялось |
| Karabas Go | `apple2.kg` | VGA, как Mini G | I2S ЦАП (PCM5102) | собрано, на плате не проверялось |

Файл ядра — `src/apple2.kg`, один на все три платы, ПЗУ Apple встроены. Нужна прошивка v26110415 или
новее. Пункты OSD ищут файлы в папке `/apple2` на SD-карте.

## Что умеет

- **Машина:** Apple //e enhanced, 65C02 (или 6502, пункт CPU) на 1,02 МГц, 64 КБ основной + 64 КБ
  дополнительной памяти (в SRAM платы), 80 колонок, lo-res / hi-res / double hi-res, динамик.
- **Disk II (слот 6), два дисковода:** `.nib` и образы 140 КБ `.dsk` / `.do` / `.po` (порядок
  секторов DOS или ProDOS узнаётся по каталогу тома, а не по расширению), чтение и запись: запись
  уходит в файл образа. Файл «только чтение» — защищённая дискета. Образ можно сменить на ходу.
- **Жёсткий диск (слот 7):** блочный образ ProDOS (`.hdv`, `.po`), чтение и запись.
- **Mockingboard (слот 4):** два AY-3-8910 со своими 6522, стерео.
- **AppleMouse (слот 5):** USB-мышь, для программ, работающих с этой картой.
- **Super Serial Card (слот 2):** пункт Serial: на USB-порт платы (скорость, заданная Apple, уходит
  в порт) или на Wi-Fi модуль платы (AT-прошивка ESP8266, 115200).
- **Джойстик:** джойстик платы или USB-геймпад — пэддлы 0 / 1 и кнопки 0 / 1.
- **Видео:** картинка //e 560 × 192 в кадре 640 × 480, цвет (артефактные цвета NTSC, четыре
  палитры) или монохромный монитор (белый, зелёный, янтарный).

Проверено на Mini G: DOS 3.3 и ProDOS 2.4 с `.nib` / `.dsk` / `.po`, `SAVE` на образы дискет и на
жёсткий диск (после повторного монтирования образа файлы на месте), смена дискеты, Mockingboard
(тоны и стерео), пэддлы и кнопки, мышь, последовательная карта на USB-порту (в обе стороны) и на
модуле ESP (`AT`, `AT+GMR`, `AT+CWLAP` из терминала карты). Нет: образов WOZ, карты Saturn 128K,
карты часов, Z80 SoftCard.

## OSD

Открывается Menu+Esc («Menu» — клавиша Windows).

| Пункт | Что делает | Клавиша |
|---|---|---|
| Disk 1, Disk 2 | образ дисковода 1 / 2 слота 6 (`.nib`, `.dsk`, `.do`, `.po`) | Menu+F1, Menu+F2 |
| Hard disk | образ ProDOS слота 7 (`.hdv`, `.po`) | Menu+F3 |
| CPU | 65C02 (enhanced //e) или 6502 | |
| Monitor | Color, B&W, Green, Amber | Menu+M |
| Palette | цвета: NTSC, IIgs, AppleWin, Custom | |
| Mockingbrd | Mockingboard в слоте 4 вкл. / выкл. | |
| Mouse | AppleMouse в слоте 5 вкл. / выкл. | |
| Serial | Super Serial Card в слоте 2: Off, USB UART, ESP Wi-Fi | |
| ESP bit 7 | (только ESP Wi-Fi) Clear: байты уходят в модуль с битом 7 = 0; Keep: все 8 бит | |
| Reset | сброс как при включении: //e загружается с дисковода 1 | F12 |

## Клавиши

| Клавиша PC | Apple //e |
|---|---|
| Ctrl+Pause | Ctrl+Reset (тёплый сброс: программа остаётся) |
| левая Windows | Open Apple |
| Alt | Closed Apple (Solid Apple) |
| F12 | Reset из OSD: холодный старт, //e загружает дискету |

## Лицензия

NanoApple2 и apple2efpga — GPL v3; части Karabas — GPL v3 (`LICENSE`). ПЗУ Apple в `src/roms`
принадлежат Apple.
