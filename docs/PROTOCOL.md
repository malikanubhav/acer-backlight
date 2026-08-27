# Acer Aspire A715-79G — Keyboard Backlight on Ubuntu

Machine: Aspire A715-79G, BIOS 1.07.01TACI, kernel 6.17.0-40-generic, Secure Boot ENABLED

## What does NOT work (verified, not guessed)
| Check | Result |
|---|---|
| `/sys/class/leds/` | no `kbd_backlight` node |
| `modprobe acer-wmi` | "No such device" |
| acer-wmi GUIDs (AMW0 67C3371D…, WMID 431F16ED…, 6AF4F258…) | all ABSENT |
| Acer gaming RGB GUID 7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56 | ABSENT → helios-rgb module cannot work |
| `AT Translated Set 2 keyboard` keycodes | emits BRIGHTNESSUP/DOWN, MEDIA, SWITCHVIDEOMODE, WLAN — NO KBDILLUM* |
| `acpi_osi` spoof | **DEAD** — see below, `_WDG` is not OSI-gated |

NOTE: the missing KBDILLUM keycode proves Linux has no software path. It does NOT prove
no physical key works — an EC-handled key never reaches the OS either.

## What DOES exist — Acer's WMI method interface

DSDT line 96051, `Device (WMI)`, `_HID PNP0C14`. `_WDG` declares exactly 3 GUIDs,
**unconditionally** (not inside any `_OSI` / `If` block — so `acpi_osi="Windows 2020"` cannot help):

| GUID | object/notify | flags | meaning |
|---|---|---|---|
| ABBC0F6D-8EA1-11D1-00A0-C90629100000 | `BB` | 0x02 | **METHOD** → ACPI method `\_SB.WMI.WMBB` |
| ABBC0F6B-8EA1-11D1-00A0-C90629100000 | 0xD0 | 0x08 | event notify |
| ABBC0F6C-8EA1-11D1-00A0-C90629100000 | 0xD1 | 0x08 | event notify |

(4th device F6CB5C3C-9CAE-4EBD-B577-931EA32A2CC0 object_id `MX` = MXM graphics, `mxm_wmi`.)

`WMBB(Arg0, Arg1, Arg2)` acquires EC mutex `^^PC00.LPCB.EC.PATM`, switches on Arg1
(function code) and dispatches to:
- `GCMD` — GET path (read)
- `SCMD` — SET path (write)
- `CC20`, `CPKG`, `OCWR` — other groups (OCWR/CC20 appear OC/fan/thermal related)

All talk to the EC via `ECMD(Buffer[8])`, e.g. `{0x02,0x80,0xB8,0xA1,0,0,0,0}`.
In `ECMD`, byte[1] & 0x80 = "read back result", byte[1] & 0x7F = stall.

**CORRECTION (2026-08-12):** an earlier draft of this file listed `0x07` as a GCMD code.
It is NOT. WMBB routes `Package(0x04){0x07,0x0C,0x0D,0x0E}` to **CC20** (OC/thermal).
`0x02`→CPKG and `0x03`→OCWR are also not getters. Authoritative lists, read from WMBB:

GET (→GCMD, 36): 01 05 06 08 09 0A 10 11 12 32 33 34 38 39 3B 3C 3D 3E 3F 41 42 43 45
                 51 52 60 62 63 64 6E 6F 70 71 73 77 7A
SET (→SCMD, 39): 13 14 1D 1F 20 21 22 26 27 2A 2C 31 46 47 48 49 4A 4C 4E 4F 55 56 57
                 5A 5B 5E 65 66 67 68 69 6A 6B 6C 6D 74 75 76 79
(verified disjoint)

## Backlight candidates found by static analysis — no probing needed to find these

**Pair A — plain backlight level (prime suspect).** EC command `0xCA`:
- GET `0x3D`: `ECMD{0x02,0x80,0xCA,0x01,0,0,0,0}` → returns **byte[2]**, a value not a bit.
- SET `0x27`: `ECMD{0x03,0x00,0xCA,0x00,ARGS,0,0,0}` → writes ARGS as the level.
Same EC command, FDAT 0x01=read / 0x00=write. Textbook getter/setter pair.

**Pair B — 4-zone RGB (Acer's PredatorSense/NitroSense path).** EC commands `0xC0/0xC2/0xC4`:
- SET `0x67`: ARGS is packed — bits 12-15 brightness (scaled `0xFF - n*0x19`, so 10 steps),
  bits 16-23 value, bits 24-27 zone, bits 28-31 mode (0=static 1..3=zone 7..0x0B=effects).
- GET `0x64, 0x6E, 0x6F, 0x70, 0x71`: `ECMD{0x02,0x80,0xC0,sub}` sub = 0x00..0x05 — the readbacks.

## Probe script
`~/kbd-backlight-probe.sh` — read-only sweep of the 36 GET codes, with a tripwire that
refuses any code not in the GET list. Note: "read-only in intent, not at register level" —
several GET branches end with `ECMD{0x01,0,...}` (writes FCMD=0), part of the vendor's own
read sequence.

**No Linux driver claims ABBC0F6D.** That is why nothing binds and no LED node appears.

## The only real path to control it from Ubuntu
1. Install `acpi-call-dkms` (lets userspace invoke arbitrary ACPI methods).
2. Secure Boot is ENABLED → must enroll a MOK key or disable Secure Boot, else the
   unsigned DKMS module won't load.
3. Enumerate **read-only** first: call `\_SB.WMI.WMBB` with the GET function codes
   and record returns. Never sweep SCMD blindly — the same interface carries
   fan/OC/thermal setters.
4. Identify the code whose getter tracks backlight state, then use its setter.

Blocker for step 3/4: identifying "backlight state" needs a known ON state to compare
against. If the light can be turned on from Windows/BIOS first, the diff becomes trivial.

## Explicitly NOT recommended
Blind `ec_sys write_support=1` register poking. Same EC carries fan curves and thermal
limits; without a known-ON state to diff, it is guessing on live thermal hardware.

## PROVEN 2026-08-13: EC command 0xCA IS the keyboard-lighting command

Inside `SCMD` fn `0x67`, mode `Local7 == 0x0F` (DSDT ~line 97420) unpacks ARGS into
three bytes and sends them via EC cmd `0xCA`, sub-command selecting the zone:

    Local3 = ARGS & 0xFF          # B
    Local2 = (ARGS >> 0x08) & 0xFF # G
    Local1 = (ARGS >> 0x10) & 0xFF # R
    -> ECMD{0x05,0x00,0xCA,<zone 0x03..0x07/0x0A>, R, G, B}

RGB triplets per keyboard zone. 0xCA is unambiguously keyboard lighting.

Thermal/fan use DIFFERENT EC commands and are never touched by our scripts:
  0xB1 (fn 0x3B), 0xC0 (fn 0x63,0x64,0x6E,0x6F,0x70,0x71 — these return temp triplets,
  e.g. 0x63 = 0x40'33'47 = 64/51/71 degC), 0xC1, 0xC2, 0xC4, 0xC6.

### First live read (2026-08-13, acpi_call loaded, MOK enrolled)
  fn 0x3D -> 0x1        <- backlight register, currently 1
  fn 0x3E -> 0x0
  fn 0x63 -> 0x403347   <- temps, drift between runs (confirms C0 = thermal)

### Control script
`~/kbd-backlight.sh` — get / set <0-255> / sweep. Writes ONLY WMBB fn 0x27.

## VERIFIED 2026-08-27: this machine is SINGLE ZONE

Painting zone indices 0,1,2,3 with different colours changes the WHOLE keyboard —
last write wins. The 4-zone code in WMBB fn 0x67 mode 0x0F is shared Nitro/Predator
firmware; on the A715-79G all zone selectors drive one LED channel.

Per-key colour is NOT possible on this hardware. Five checks:
  1. DSDT: EC cmd 0xCA takes one selector + one RGB triplet. No key index anywhere.
  2. lsusb: no ITE 8291/8297/8298 or Holtek LED controller present.
  3. i2c: only FTCS1000 (touchpad). No LED controller.
  4. /sys/class/leds: nothing for the keyboard.
  5. Keyboard is "AT Translated Set 2 keyboard" - legacy EC path, no lighting endpoint.

DO NOT write zone indices 4, 5 or 6. Index 4 -> EC sub 0x06, index 6 -> two-step
0x09 then 0x0A. Writing these on 2026-08-27 latched the controller off; recovery
needed the master enable (fn 0x67 mode 0x04 -> EC 0xC4 0x0D), now sent automatically
by acer-backlight before any non-black colour, and exposed as `acer-backlight on` / `acer-backlight reset`.

## CLOSED 2026-08-27: per-key confirmed impossible, including on Windows

The owner verified that Acer's own Windows software cannot set a single key's colour
on this machine either. That closes the question — it is a hardware limit, not a
Linux driver gap. Single LED channel, whole keyboard, one colour at a time.

Final capability ceiling for the A715-79G:
  - any RGB colour, whole keyboard          WORKS
  - brightness 0-100%                       WORKS (RGB scaling)
  - persistence across boot + suspend       WORKS (systemd unit)
  - zones                                   NONE (single-zone hardware)
  - firmware effects (modes 0x07-0x0B)      accepted but no visible effect
                                            (they animate across zones; there is one)
  - per-key colour                          IMPOSSIBLE — no LED matrix controller
