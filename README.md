<p align="center">
  <img src="share/acer-backlight.svg" width="128" height="128" alt="Acer Backlight">
</p>

<h1 align="center">Acer Backlight</h1>

<p align="center">
  RGB keyboard backlight control for Acer laptops that Linux has no driver for.
</p>

Some Acer laptops expose their keyboard lighting through WMI GUID
`ABBC0F6D-8EA1-11D1-00A0-C90629100000`. Mainline `acer-wmi` binds a different set of
GUIDs, so nothing claims this one — no `/sys/class/leds` node ever appears, the Fn key
does nothing, and there is no way to change the colour from Linux.

This drives it from userspace instead: a CLI plus a GTK4 app with a colour wheel.

```
sudo acer-backlight purple
sudo acer-backlight -b 40 warm
sudo acer-backlight off
```

## Does it work on my laptop?

```
acer-backlight detect
```

| Your machine | Status |
|---|---|
| Acer exposing `ABBC0F6D-…` (Aspire family) | **Supported** — run `acer-backlight calibrate` once |
| Acer Predator / Nitro (`7A4DDFE7-…`) | Use [Linuwu-Sense](https://github.com/0x7375646F/Linuwu-Sense) |
| Older Acer (`67C3371D-…`, `431F16ED-…`) | Mainline `acer-wmi` — on/off only |
| Any non-Acer | Not supported. Different vendors, different protocols. |

`detect` refuses to write anything if the GUID is absent.

Developed and verified on an **Aspire A715-79G** (BIOS 1.07.01TACI, kernel 6.17,
Ubuntu 24.04, Secure Boot on). Reports from other models welcome.

## Install

```bash
git clone https://github.com/malikanubhav/acer-backlight.git
cd acer-backlight
sudo ./install.sh
```

The installer pulls in what it needs — `acpi-call-dkms`, `python3-gi`, `python3-cairo`,
`python3-gi-cairo`, `gir1.2-gtk-4.0`, `gir1.2-adw-1` — on Debian and Ubuntu. On other
distros it lists them and stops rather than guessing package names. Skip the automatic
step with `sudo SKIP_DEPS=1 ./install.sh`.

### Secure Boot

`acpi-call-dkms` is compiled on your machine, so it is signed by nobody and Secure Boot
refuses to load it. During `apt install` you are asked to set a one-time password.
Reboot, choose **Enroll MOK** on the blue screen, and enter it. That registers your own
signing key — a one-time step, and it keeps Secure Boot enabled.

Check your state with `mokutil --sb-state`.

## Update

```
sudo acer-backlight update
```

Fetches the latest release and reinstalls. It clones fresh into a temporary directory,
so it works even if you deleted your original checkout. `acer-backlight version` shows
what you have.

## Calibrate

The three colour bytes are unlabelled in firmware and their order differs between
models. On a machine other than the A715-79G, run:

```
sudo acer-backlight calibrate
```

It lights one channel at a time and asks what you see. Two questions, plus one about
zone count. The answers are written to `/etc/acer-backlight.conf`.

## Usage

```
acer-backlight white | ff8000 | off      colour by name or hex
acer-backlight -b 0-100 <colour>         brightness
acer-backlight 2 red                     one zone (0-3), on multi-zone models
acer-backlight detect                    identify this machine
acer-backlight calibrate                 discover channel order + zone count
acer-backlight update                    fetch the latest version and reinstall
acer-backlight version                   show the installed version
acer-backlight reset                     recovery, if the controller stops responding
```

Colours: `white red green blue yellow cyan magenta purple orange pink teal warm off`

Your colour is restored at boot and after resume by a systemd unit. Change the default
in `/etc/default/acer-backlight`.

## Safety

- Only ACPI function `0x67` (keyboard lighting) is ever written.
- Fan and thermal commands (`0xB1`, `0xC0`, `0xC1`, `0xC6`, `0xCC`) are never touched.
  `0xCC` computes against `MXTJ`, the CPU max junction temperature — writing it would
  alter your fan curve.
- Zone indices 4, 5 and 6 are excluded in code. They reach undocumented EC
  sub-commands and latched the controller off during development. Recovery is
  `acer-backlight reset`, or a full power-off.

## Uninstall

```
sudo ./install.sh uninstall
```

Removes the binaries, systemd unit, icon, desktop entry and the sudoers rule.

## Why passwordless sudo

Writing `/proc/acpi/call` needs root, but a GUI should not run as root. The installer
adds `/etc/sudoers.d/acer-backlight` granting NOPASSWD for that one binary. `acer-backlight`
validates every argument, never evaluates input, and only writes the lighting function.

Skip it with `sudo SKIP_SUDOERS=1 ./install.sh` — the GUI will then prompt for a
password on every change.

## Contributing

Most valuable contribution: run `acer-backlight detect` and `acer-backlight calibrate` on another
Acer model and open an issue with the output. Channel order and zone count vary, and
every confirmed model makes the tool work for more people.

## Licence

MIT. See [LICENSE](LICENSE).
