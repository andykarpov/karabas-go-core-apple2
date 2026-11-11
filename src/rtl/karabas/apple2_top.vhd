-- apple2_top.vhd
--
-- karabas: the Apple //e machine with its cards, as the NanoApple2 top (upstream/primer25k/
-- nanoapple2.vhd) wires them, without the board: no PLL, SDRAM, MCU, HDMI or OSD. VHDL-93 for XST.
--
--   slot 2 SSC, slot 4 Mockingboard A, slot 5 AppleMouse, slot 6 Disk II (two drives, .NIB),
--   slot 7 ProDOS HDD (.HDV)
--
-- Outside: the 64K main + 64K aux RAM (ram_dout = aux & main at ram_addr, one write port; the
-- read must be registered on clk_core, see apple2_sram), the Apple video (VIDEO / COLOR_LINE /
-- HBL / VBL at 14 MHz: apple2_fb colours it), the speaker and the two PSG channels, the keyboard
-- (MiSTeryNano usb_key), the paddles / buttons, the mouse, the SD sector interface of three images
-- (0 / 1 floppies, 2 HDD) as img_sdc has it, and the SSC UART.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity apple2_top is
  port (
    clk_core       : in  std_logic;                     -- 14.31818 MHz
    clk_sys        : in  std_logic;                     -- 28.63636 MHz, the SD side
    reset_cold     : in  std_logic;                     -- power up: clears the reset vector
    reset_warm     : in  std_logic;                     -- Ctrl+Reset

    -- options
    cpu_type       : in  std_logic;                     -- 0 6502, 1 65C02
    romswitch      : in  std_logic;                     -- video ROM half
    color_text     : in  std_logic;                     -- colour text in mixed lo-res (colour monitor)
    mono           : in  std_logic;                     -- a monochrome monitor: no colour lines
    mb_en          : in  std_logic;
    mouse_en       : in  std_logic;
    ssc_en         : in  std_logic;
    ssc_irq_en     : in  std_logic;
    hdd_en         : in  std_logic;
    floppy_wp      : in  std_logic_vector(1 downto 0);
    hdd_wp         : in  std_logic;

    -- RAM
    ram_addr       : out std_logic_vector(15 downto 0);
    ram_aux        : out std_logic;
    ram_we         : out std_logic;
    ram_din        : out std_logic_vector(7 downto 0);
    ram_dout       : in  std_logic_vector(15 downto 0); -- aux & main

    -- video (14 MHz): color_line already with color_text / mono
    video          : out std_logic;
    color_line     : out std_logic;
    hbl            : out std_logic;
    vbl            : out std_logic;

    -- sound
    speaker        : out std_logic;
    psg_l          : out std_logic_vector(9 downto 0);
    psg_r          : out std_logic_vector(9 downto 0);

    -- keyboard
    usb_key        : in  std_logic_vector(7 downto 0);
    kbd_strobe     : in  std_logic;
    soft_reset     : out std_logic;

    -- game port: paddles (signed, 0 = centre) and buttons 0 / 1
    paddle_x       : in  std_logic_vector(7 downto 0);
    paddle_y       : in  std_logic_vector(7 downto 0);
    joy_btn        : in  std_logic_vector(1 downto 0);

    -- mouse
    mouse_strobe   : in  std_logic;
    mouse_x        : in  std_logic_vector(8 downto 0);
    mouse_y        : in  std_logic_vector(8 downto 0);
    mouse_btn      : in  std_logic;

    -- SD sectors of the images: 0 floppy A, 1 floppy B, 2 HDD
    img_mounted    : in  std_logic_vector(2 downto 0);
    img_size       : in  std_logic_vector(31 downto 0);
    sd_lba         : out std_logic_vector(31 downto 0);
    sd_rd          : out std_logic_vector(2 downto 0);
    sd_wr          : out std_logic_vector(2 downto 0);
    sd_busy        : in  std_logic;
    sd_slot        : in  std_logic_vector(2 downto 0);  -- the image being served (img_sdc)
    sd_byte_index  : in  std_logic_vector(8 downto 0);
    sd_rd_data     : in  std_logic_vector(7 downto 0);
    sd_rd_byte_strobe : in std_logic;
    sd_wr_data     : out std_logic_vector(7 downto 0);

    -- SSC
    uart_rx        : in  std_logic;
    uart_tx        : out std_logic;

    disk_active    : out std_logic_vector(1 downto 0)
  );
end apple2_top;

architecture rtl of apple2_top is

  signal CLK_2M, CLK_2M_D, PHASE_ZERO, PHASE_ZERO_R, PHASE_ZERO_F : std_logic;
  signal IO_SELECT, DEVICE_SELECT : std_logic_vector(7 downto 0);
  signal IO_STROBE : std_logic;
  signal ADDR : unsigned(15 downto 0);
  signal D, PD : unsigned(7 downto 0);
  signal DO : std_logic_vector(15 downto 0);
  signal a_ram : unsigned(15 downto 0);
  signal we_ram, aux, cpu_we, irq_n : std_logic;
  signal K : unsigned(7 downto 0);
  signal read_key, akd, open_apple, closed_apple : std_logic;
  signal GAMEPORT : std_logic_vector(7 downto 0);
  signal pdl_strobe : std_logic;
  signal joyx, joyy : std_logic;
  signal VIDEO_i, COLOR_LINE_i, HBL_i, VBL_i, TEXT_MODE : std_logic;
  signal COLOR_LINE_CONTROL, TEXT_COLOR : std_logic;

  signal reset, reset_w, power_on_reset, dd_reset, soft_reset_i : std_logic := '1';
  signal flash_clk : unsigned(22 downto 0) := (others => '0');

  signal PSG_DO, DISK_DO, HDD_DO, SSC_DO, MOUSE_DO : unsigned(7 downto 0);
  signal PSG_DO_v : std_logic_vector(7 downto 0);
  signal psg_irq_n, ssc_irq_n, mouse_irq_n, SSC_OE, MOUSE_OE : std_logic;
  signal mb_reset_n, mb_rw_n, mb_iosel_n : std_logic;
  signal rnw : std_logic;

  -- floppies
  signal TRACK1, TRACK2 : unsigned(5 downto 0);
  signal TRACK1_RAM_ADDR, TRACK2_RAM_ADDR : unsigned(12 downto 0);
  signal TRACK1_RAM_DI, TRACK2_RAM_DI, TRACK1_RAM_DO, TRACK2_RAM_DO : unsigned(7 downto 0);
  signal TRACK1_DO_v, TRACK2_DO_v : std_logic_vector(7 downto 0);
  signal TRACK1_RAM_WE, TRACK2_RAM_WE, TRACK1_RAM_BUSY, TRACK2_RAM_BUSY : std_logic;
  signal D1_ACTIVE, D2_ACTIVE : std_logic;
  signal DISK_READY, DISK_MOUNT, DISK_CHANGE, disk_mount_d : std_logic_vector(1 downto 0) := "00";
  signal DISK_DSK, disk_new : std_logic_vector(1 downto 0) := "00";  -- karabas: 140K sector images, a new mount
  signal disk_chg_trg, disk_chg_trg_d : std_logic := '0';
  signal SD_LBA1, SD_LBA2, SD_LBA3 : std_logic_vector(31 downto 0);
  signal SD_DATA_IN1, SD_DATA_IN2 : std_logic_vector(7 downto 0);
  signal SD_DATA_IN3 : unsigned(7 downto 0);
  signal sd_rd_i, sd_wr_i : std_logic_vector(2 downto 0);
  signal track1_v, track2_v : std_logic_vector(5 downto 0);
  signal trk1_addr_v, trk2_addr_v : std_logic_vector(12 downto 0);
  signal trk1_di_v, trk2_di_v : std_logic_vector(7 downto 0);

  -- HDD
  signal sector : unsigned(15 downto 0);
  signal hdd_read, hdd_write, hdd_mounted, hdd_protect : std_logic := '0';
  signal hdd_readD, hdd_readD2, hdd_writeD, hdd_writeD2 : std_logic := '0';
  signal hdd_read_pending, hdd_write_pending, old_ack : std_logic := '0';
  signal cpu_wait_hdd, cpu_wait_hddD, cpu_wait_hddD2 : std_logic := '0';
  signal hdd_state : std_logic_vector(1 downto 0) := "00";
  signal hdd_ram_we : std_logic;
  signal sd_ack : std_logic_vector(2 downto 0);     -- sd_busy of each image

  -- SSC
  signal ssc_sw1 : std_logic_vector(6 downto 1);
  signal ssc_sw2 : std_logic_vector(5 downto 1);
  signal nullmdm1, nullmdm2 : std_logic;

begin

  -- In the Apple ][, this was a 555 timer
  power_on : process(clk_core)
  begin
    if rising_edge(clk_core) then
      reset    <= reset_w or power_on_reset;
      reset_w  <= reset_warm;
      dd_reset <= reset_cold or soft_reset_i;
      if reset_cold = '1' or soft_reset_i = '1' then
        power_on_reset <= '1';
        flash_clk <= (others => '0');
      else
        if flash_clk(22) = '1' then
          power_on_reset <= '0';
        end if;
        flash_clk <= flash_clk + 1;
      end if;
    end if;
  end process;

  -- simulate power up on cold reset to go to the disk boot routine: clear $3F4
  ram_we   <= we_ram when reset_cold = '0' else '1';
  ram_addr <= std_logic_vector(a_ram) when reset_cold = '0' else std_logic_vector(to_unsigned(1012, 16));
  ram_din  <= std_logic_vector(D) when reset_cold = '0' else "00000000";
  ram_aux  <= aux;
  DO       <= ram_dout;

  PD <= PSG_DO   when IO_SELECT(4) = '1' and mb_en = '1' else
        SSC_DO   when SSC_OE = '1' and ssc_en = '1' else
        HDD_DO   when (IO_SELECT(7) = '1' or DEVICE_SELECT(7) = '1') and hdd_en = '1' else
        MOUSE_DO when MOUSE_OE = '1' and mouse_en = '1' else
        DISK_DO;

  irq_n <= '0' when (psg_irq_n = '0' and mb_en = '1')
                 or (mouse_irq_n = '0' and mouse_en = '1')
                 or (ssc_irq_n = '0' and ssc_en = '1' and ssc_irq_en = '1') else '1';

  core : entity work.apple2 port map (
    CLK_14M        => clk_core,
    CLK_2M         => CLK_2M,
    CPU_WAIT       => cpu_wait_hdd,
    PHASE_ZERO     => PHASE_ZERO,
    PHASE_ZERO_R   => PHASE_ZERO_R,
    PHASE_ZERO_F   => PHASE_ZERO_F,
    FLASH_CLK      => flash_clk(22),
    reset          => reset,
    cpu            => cpu_type,
    ADDR           => ADDR,
    ram_addr       => a_ram,
    D              => D,
    ram_do         => unsigned(DO),
    aux            => aux,
    PD             => PD,
    CPU_WE         => cpu_we,
    IRQ_N          => irq_n,
    NMI_N          => '1',
    ram_we         => we_ram,
    VIDEO          => VIDEO_i,
    PALMODE        => '0',
    ROMSWITCH      => romswitch,
    COLOR_LINE     => COLOR_LINE_i,
    TEXT_MODE      => TEXT_MODE,
    HBL            => HBL_i,
    VBL            => VBL_i,
    K              => K,
    KEYSTROBE      => read_key,
    AKD            => akd,
    AN             => open,
    GAMEPORT       => GAMEPORT,
    PDL_strobe     => pdl_strobe,
    STB            => open,
    IO_SELECT      => IO_SELECT,
    DEVICE_SELECT  => DEVICE_SELECT,
    IO_STROBE      => IO_STROBE,      -- karabas: undriven in the NanoApple2 top (no SSC $C800 ROM)
    speaker       => speaker,
    ioctl_addr     => (others => '0'),
    ioctl_data     => (others => '0'),
    ioctl_index    => (others => '0'),
    ioctl_download => '0',
    ioctl_wr       => '0',
    ioctl_clk      => clk_sys
  );

  video      <= VIDEO_i;
  hbl        <= HBL_i;
  vbl        <= VBL_i;

  -- as the NanoApple2 top: colour text lines in mixed modes on request, none on a monochrome monitor
  TEXT_COLOR <= color_text;
  COLOR_LINE_CONTROL <= (COLOR_LINE_i or (TEXT_COLOR and not TEXT_MODE)) and not mono;
  color_line <= COLOR_LINE_CONTROL;

  keyboard : entity work.keyboard port map (
    usb_key        => usb_key,
    kbd_strobe     => kbd_strobe,
    CLK_14M        => clk_core,
    reset          => reset_cold,
    reads          => read_key,
    K              => K,
    akd            => akd,
    open_apple     => open_apple,
    closed_apple   => closed_apple,
    soft_reset     => soft_reset_i,
    video_toggle   => open,
    palette_toggle => open
  );
  soft_reset <= soft_reset_i;

  -- game port: 7..4 pdl3..pdl0, 3..1 pb3..pb1, 0 cassette in
  GAMEPORT <= "00" & joyy & joyx & '0' & (joy_btn(1) or closed_apple) & (joy_btn(0) or open_apple) & uart_rx;

  -- the 558 timers of the paddles
  paddles : process(clk_core)
    variable cx, cy : integer range -100 to 5800 := 0;
  begin
    if rising_edge(clk_core) then
      CLK_2M_D <= CLK_2M;
      if CLK_2M_D = '0' and CLK_2M = '1' then
        if cx > 0 then
          cx := cx - 1;
          joyx <= '1';
        else
          joyx <= '0';
        end if;
        if cy > 0 then
          cy := cy - 1;
          joyy <= '1';
        else
          joyy <= '0';
        end if;
        if pdl_strobe = '1' then
          cx := 2800 + (22 * to_integer(signed(paddle_x)));
          cy := 2800 + (22 * to_integer(signed(paddle_y)));
          if cx < 0 then
            cx := 0;
          elsif cx >= 5590 then
            cx := 5650;
          end if;
          if cy < 0 then
            cy := 0;
          elsif cy >= 5590 then
            cy := 5650;
          end if;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- SD: the request of the image being served picks the LBA and the write data

  SD_LBA3    <= x"0000" & std_logic_vector(sector);
  sd_lba     <= SD_LBA3 when (sd_rd_i(2) or sd_wr_i(2)) = '1' else
                SD_LBA2 when (sd_rd_i(1) or sd_wr_i(1)) = '1' else
                SD_LBA1;
  -- karabas: the write data and the acks by the slot img_sdc serves (the requests drop when it
  -- takes them; upstream picked the data by the request, so a write of drive 2 sent drive 1's track)
  sd_wr_data <= std_logic_vector(SD_DATA_IN3) when sd_slot = "010" else
                SD_DATA_IN2 when sd_slot = "001" else
                SD_DATA_IN1;
  sd_ack(0) <= sd_busy when sd_slot = "000" else '0';
  sd_ack(1) <= sd_busy when sd_slot = "001" else '0';
  sd_ack(2) <= sd_busy when sd_slot = "010" else '0';
  sd_rd <= sd_rd_i;
  sd_wr <= sd_wr_i;

  -- mounting: a change of an image (or 2.2 s after start, as upstream) reloads the track.
  -- karabas: the mounts stay over a reset (upstream cleared them only without the PLL): the
  -- firmware sends img_mounted once, at the mount; a cleared DISK_MOUNT took the disk away for good
  mount : process(clk_sys)
    variable reset_cnt : integer range 0 to 67108863 := 64000000;
  begin
    if rising_edge(clk_sys) then
      disk_mount_d   <= DISK_MOUNT;
      disk_chg_trg_d <= disk_chg_trg;
      if reset_cold = '1' then
        disk_chg_trg <= '0';
        reset_cnt := 64000000;
      else
        if reset_cnt /= 0 then
          reset_cnt := reset_cnt - 1;
        else
          disk_chg_trg <= '1';
        end if;
        disk_new <= "00";
        if img_mounted(0) = '1' then
          if unsigned(img_size) = 0 then DISK_MOUNT(0) <= '0'; else DISK_MOUNT(0) <= '1'; end if;
          if unsigned(img_size) = 143360 then DISK_DSK(0) <= '1'; else DISK_DSK(0) <= '0'; end if;
          disk_new(0) <= '1';
        elsif img_mounted(1) = '1' then
          if unsigned(img_size) = 0 then DISK_MOUNT(1) <= '0'; else DISK_MOUNT(1) <= '1'; end if;
          if unsigned(img_size) = 143360 then DISK_DSK(1) <= '1'; else DISK_DSK(1) <= '0'; end if;
          disk_new(1) <= '1';
        elsif img_mounted(2) = '1' then
          if unsigned(img_size) = 0 then hdd_mounted <= '0'; else hdd_mounted <= '1'; end if;
          hdd_protect <= hdd_wp;
        end if;
      end if;

      for i in 0 to 1 loop
        -- karabas: also a new image over the old one (disk_new: DISK_MOUNT stays 1 then)
        if DISK_MOUNT(i) /= disk_mount_d(i) or disk_new(i) = '1' or (disk_chg_trg_d = '0' and disk_chg_trg = '1') then
          DISK_CHANGE(i) <= '1';
        else
          DISK_CHANGE(i) <= '0';
        end if;
      end loop;
    end if;
  end process;

  track1_v    <= std_logic_vector(TRACK1);
  track2_v    <= std_logic_vector(TRACK2);
  trk1_addr_v <= std_logic_vector(TRACK1_RAM_ADDR);
  trk2_addr_v <= std_logic_vector(TRACK2_RAM_ADDR);
  trk1_di_v   <= std_logic_vector(TRACK1_RAM_DI);
  trk2_di_v   <= std_logic_vector(TRACK2_RAM_DI);
  TRACK1_RAM_DO <= unsigned(TRACK1_DO_v);
  TRACK2_RAM_DO <= unsigned(TRACK2_DO_v);

  -- karabas: apple2_floppy (floppy_track of NanoApple2 plus the 140K sector images)
  drive1 : entity work.apple2_floppy port map (
    clk          => clk_core,
    clk2         => clk_sys,
    reset        => dd_reset,
    ram_addr     => trk1_addr_v,
    ram_di       => trk1_di_v,
    ram_do       => TRACK1_DO_v,
    ram_we       => TRACK1_RAM_WE,
    track        => track1_v,
    busy         => TRACK1_RAM_BUSY,
    change       => DISK_CHANGE(0),
    mount        => DISK_MOUNT(0),
    dsk          => DISK_DSK(0),
    ready        => DISK_READY(0),
    active       => D1_ACTIVE,
    sd_buff_addr => sd_byte_index,
    sd_buff_dout => sd_rd_data,
    sd_buff_din  => SD_DATA_IN1,
    sd_buff_wr   => sd_rd_byte_strobe,
    sd_lba       => SD_LBA1,
    sd_rd        => sd_rd_i(0),
    sd_wr        => sd_wr_i(0),
    sd_ack       => sd_ack(0)
  );

  drive2 : entity work.apple2_floppy port map (
    clk          => clk_core,
    clk2         => clk_sys,
    reset        => dd_reset,
    ram_addr     => trk2_addr_v,
    ram_di       => trk2_di_v,
    ram_do       => TRACK2_DO_v,
    ram_we       => TRACK2_RAM_WE,
    track        => track2_v,
    busy         => TRACK2_RAM_BUSY,
    change       => DISK_CHANGE(1),
    mount        => DISK_MOUNT(1),
    dsk          => DISK_DSK(1),
    ready        => DISK_READY(1),
    active       => D2_ACTIVE,
    sd_buff_addr => sd_byte_index,
    sd_buff_dout => sd_rd_data,
    sd_buff_din  => SD_DATA_IN2,
    sd_buff_wr   => sd_rd_byte_strobe,
    sd_lba       => SD_LBA2,
    sd_rd        => sd_rd_i(1),
    sd_wr        => sd_wr_i(1),
    sd_ack       => sd_ack(1)
  );

  disk : entity work.disk_ii port map (
    CLK_14M        => clk_core,
    CLK_2M         => CLK_2M,
    PHASE_ZERO     => PHASE_ZERO,
    IO_SELECT      => IO_SELECT(6),
    DEVICE_SELECT  => DEVICE_SELECT(6),
    RESET          => reset,
    DISK_READY     => DISK_READY,
    A              => ADDR,
    D_IN           => D,
    D_OUT          => DISK_DO,
    D1_ACTIVE      => D1_ACTIVE,
    D2_ACTIVE      => D2_ACTIVE,
    D1_WP          => floppy_wp(0) or DISK_DSK(0),  -- karabas: sector images read only (for now)
    D2_WP          => floppy_wp(1) or DISK_DSK(1),
    TRACK1         => TRACK1,
    TRACK1_ADDR    => TRACK1_RAM_ADDR,
    TRACK1_DO      => TRACK1_RAM_DO,
    TRACK1_DI      => TRACK1_RAM_DI,
    TRACK1_WE      => TRACK1_RAM_WE,
    TRACK1_BUSY    => TRACK1_RAM_BUSY,
    TRACK2         => TRACK2,
    TRACK2_ADDR    => TRACK2_RAM_ADDR,
    TRACK2_DO      => TRACK2_RAM_DO,
    TRACK2_DI      => TRACK2_RAM_DI,
    TRACK2_WE      => TRACK2_RAM_WE,
    TRACK2_BUSY    => TRACK2_RAM_BUSY
  );
  disk_active <= D2_ACTIVE & D1_ACTIVE;

  ---------------------------------------------------------------------------
  -- slot 4: Mockingboard A

  mb_reset_n <= not reset;
  mb_rw_n    <= not cpu_we;
  mb_iosel_n <= not IO_SELECT(4);

  mb : entity work.mockingboard port map (
    CLK_14M      => clk_core,
    PHASE_ZERO   => PHASE_ZERO,
    PHASE_ZERO_R => PHASE_ZERO_R,
    PHASE_ZERO_F => PHASE_ZERO_F,
    I_RESET_L    => mb_reset_n,
    I_ENA_H      => mb_en,
    I_ADDR       => std_logic_vector(ADDR(7 downto 0)),
    I_DATA       => std_logic_vector(D),
    O_DATA       => PSG_DO_v,
    I_RW_L       => mb_rw_n,
    I_IOSEL_L    => mb_iosel_n,
    O_IRQ_L      => psg_irq_n,
    O_NMI_L      => open,
    O_AUDIO_L    => psg_l,
    O_AUDIO_R    => psg_r
  );
  PSG_DO <= unsigned(PSG_DO_v);

  ---------------------------------------------------------------------------
  -- slot 7: HDD, one SD request per block, the CPU waits

  rnw        <= not cpu_we;
  hdd_ram_we <= sd_rd_byte_strobe and sd_ack(2);

  hdd : entity work.hdd port map (
    CLK_14M        => clk_core,
    clk2           => clk_sys,
    IO_SELECT      => IO_SELECT(7),
    DEVICE_SELECT  => DEVICE_SELECT(7),
    RESET          => reset,
    A              => ADDR,
    RD             => rnw,
    D_IN           => D,
    D_OUT          => HDD_DO,
    sector         => sector,
    hdd_read       => hdd_read,
    hdd_write      => hdd_write,
    hdd_mounted    => hdd_mounted,
    hdd_protect    => hdd_protect,
    ram_addr       => unsigned(sd_byte_index),
    ram_di         => unsigned(sd_rd_data),
    ram_do         => SD_DATA_IN3,
    ram_we         => hdd_ram_we
  );

  process(clk_core)
  begin
    if rising_edge(clk_core) then
      cpu_wait_hddD <= cpu_wait_hddD2;
      cpu_wait_hdd  <= cpu_wait_hddD;
    end if;
  end process;

  process(clk_sys, dd_reset)
  begin
    if dd_reset = '1' then
      hdd_state         <= "00";
      cpu_wait_hddD2    <= '0';
      hdd_read_pending  <= '0';
      hdd_write_pending <= '0';
      sd_rd_i(2)        <= '0';
      sd_wr_i(2)        <= '0';
    elsif rising_edge(clk_sys) then
      hdd_readD   <= hdd_read;
      hdd_readD2  <= hdd_readD;
      hdd_writeD  <= hdd_write;
      hdd_writeD2 <= hdd_writeD;
      old_ack     <= sd_ack(2);
      if hdd_readD = '0' and hdd_readD2 = '1' then
        hdd_read_pending <= '1';
      end if;
      if hdd_writeD = '0' and hdd_writeD2 = '1' then
        hdd_write_pending <= '1';
      end if;

      case hdd_state is
        when "00" =>
          hdd_state <= "01";
        when "01" =>
          if hdd_read_pending = '1' or hdd_write_pending = '1' then
            hdd_state      <= "10";
            sd_rd_i(2)     <= hdd_read_pending;
            sd_wr_i(2)     <= hdd_write_pending;
            cpu_wait_hddD2 <= '1';
          end if;
        when "10" =>
          if old_ack = '0' and sd_ack(2) = '1' then
            hdd_read_pending  <= '0';
            hdd_write_pending <= '0';
            sd_rd_i(2)        <= '0';
            sd_wr_i(2)        <= '0';
          elsif old_ack = '1' and sd_ack(2) = '0' then
            hdd_state      <= "00";
            cpu_wait_hddD2 <= '0';
          end if;
        when others =>
          hdd_state <= "00";
      end case;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- slot 2: Super Serial Card, 9600 8N1 (SW1 / SW2 as the upstream defaults)

  ssc_sw1 <= "000111";   -- 9600 baud, the default of the upstream OSD (value 14, bits reversed)
  ssc_sw2 <= "00010";    -- 8 data bits, no parity, 1 stop bit, no LF after CR
  nullmdm1 <= '0';
  nullmdm2 <= '0';

  ssc : entity work.ssc port map (
    CLK_14M        => clk_core,
    CLK_2M         => CLK_2M,
    PHASE_ZERO     => PHASE_ZERO,
    IO_SELECT      => IO_SELECT(2),
    IO_STROBE      => IO_STROBE,
    DEVICE_SELECT  => DEVICE_SELECT(2),
    RESET          => reset,
    A              => ADDR,
    RNW            => rnw,
    D_IN           => D,
    D_OUT          => SSC_DO,
    OE             => SSC_OE,
    IRQ_N          => ssc_irq_n,
    SW1            => ssc_sw1,
    SW2            => ssc_sw2,
    UART_RX        => uart_rx,
    UART_TX        => uart_tx,
    UART_CTS       => nullmdm1,
    UART_RTS       => open,
    UART_DCD       => nullmdm2,
    UART_DSR       => nullmdm2,
    UART_DTR       => open,
    clk_sys        => clk_sys,
    wifimodem      => '0',
    serial_data_out_available => open,
    serial_data_in_free       => open,
    serial_strobe_out         => '0',
    serial_data_out           => open,
    serial_status_out         => open,
    serial_strobe_in          => '0',
    serial_data_in            => (others => '0')
  );

  ---------------------------------------------------------------------------
  -- slot 5: AppleMouse

  mouse : entity work.applemouse port map (
    CLK_14M        => clk_core,
    CLK_2M         => CLK_2M,
    PHASE_ZERO     => PHASE_ZERO,
    IO_SELECT      => IO_SELECT(5),
    IO_STROBE      => IO_STROBE,
    DEVICE_SELECT  => DEVICE_SELECT(5),
    RESET          => reset,
    A              => ADDR,
    RNW            => rnw,
    D_IN           => D,
    D_OUT          => MOUSE_DO,
    OE             => MOUSE_OE,
    IRQ_N          => mouse_irq_n,
    STROBE         => mouse_strobe,
    X              => signed(mouse_x),
    Y              => signed(mouse_y),
    BUTTON         => mouse_btn
  );

end rtl;
