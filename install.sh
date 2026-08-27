#!/bin/bash
# Acer Backlight — installer.
#   sudo ./install.sh              install
#   sudo ./install.sh uninstall    remove everything, sudoers rule included
#   sudo SKIP_SUDOERS=1 ./install.sh   install without passwordless sudo (GUI will prompt)
set -eu

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=/usr/local/bin/acer-backlight
GUI=/usr/local/bin/acer-backlight-gui
CONF=/etc/default/acer-backlight
UNIT=/etc/systemd/system/acer-backlight.service
MODC=/etc/modules-load.d/acpi_call.conf
SUDOD=/etc/sudoers.d/acer-backlight
DESK=/usr/share/applications/acer-backlight.desktop
ICON=/usr/share/icons/hicolor/scalable/apps/acer-backlight.svg
SLEEP=/usr/lib/systemd/system-sleep/acer-backlight

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

if [[ ${1:-install} == uninstall ]]; then
    systemctl disable --now acer-backlight.service 2>/dev/null || true
    rm -f "$BIN" "$GUI" "$UNIT" "$MODC" "$CONF" "$SUDOD" "$DESK" "$ICON" "$SLEEP" /etc/acer-backlight.conf
    systemctl daemon-reload
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf /usr/share/icons/hicolor || true
    echo "removed."
    exit 0
fi

# --- dependencies ---------------------------------------------------------
# Package names are Debian/Ubuntu. On other distros the script reports what is
# missing and stops rather than guessing at package names.
need_pkgs=()
python3 -c "import gi; gi.require_version('Gtk','4.0'); gi.require_version('Adw','1')" 2>/dev/null \
    || need_pkgs+=(python3-gi gir1.2-gtk-4.0 gir1.2-adw-1)
# python3-gi-cairo provides gi._gi_cairo, the PyGObject<->cairo bridge. Without it the
# colour wheel silently fails to draw while the rest of the window works fine.
python3 -c "import cairo, gi._gi_cairo" 2>/dev/null \
    || need_pkgs+=(python3-cairo python3-gi-cairo)
modinfo acpi_call >/dev/null 2>&1 || need_pkgs+=(acpi-call-dkms)

if (( ${#need_pkgs[@]} )) && [[ ${SKIP_DEPS:-} != 1 ]]; then
    if ! command -v apt-get >/dev/null; then
        echo "Missing dependencies, and this is not a Debian/Ubuntu system."
        echo "Install the equivalents of: ${need_pkgs[*]}"
        exit 1
    fi
    echo "Installing dependencies: ${need_pkgs[*]}"
    if [[ " ${need_pkgs[*]} " == *acpi-call-dkms* ]] && [[ $(mokutil --sb-state 2>/dev/null) == *enabled* ]]; then
        cat <<'W'

  ┌──────────────────────────────────────────────────────────────┐
  │  Secure Boot is ON.                                          │
  │  acpi-call-dkms will ask you to invent a one-time password.  │
  │  Write it down. After this finishes:                         │
  │    1. reboot                                                 │
  │    2. choose "Enroll MOK" on the blue screen                 │
  │    3. enter that password                                    │
  │  The module cannot load until you do.                        │
  └──────────────────────────────────────────────────────────────┘

W
        read -rp "  Press Enter to continue, Ctrl+C to abort " _ || true
    fi
    apt-get update -qq || true
    apt-get install -y "${need_pkgs[@]}" || { echo "apt failed — install manually: ${need_pkgs[*]}"; exit 1; }
fi

# --- files ----------------------------------------------------------------
install -m 755 "$SRC/bin/acer-backlight"      "$BIN"
install -m 755 "$SRC/bin/acer-backlight-gui"  "$GUI"
install -D -m 644 "$SRC/share/acer-backlight.svg" "$ICON"
echo "acpi_call" > "$MODC"

[[ -f $CONF ]] || cat > "$CONF" <<'C'
# Colour restored at boot and after resume.
# Any acer-backlight colour name or 6-digit hex.
COLOR=warm
BRIGHT=60
C

cat > "$UNIT" <<'U'
[Unit]
Description=Restore keyboard backlight colour
After=multi-user.target suspend.target hibernate.target suspend-then-hibernate.target

[Service]
Type=oneshot
EnvironmentFile=-/etc/default/acer-backlight
ExecStartPre=/sbin/modprobe acpi_call
ExecStart=/bin/sh -c '/usr/local/bin/acer-backlight -b "${BRIGHT:-60}" "${COLOR:-warm}"'
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
U

# Resume is handled here, not by the unit. A unit that is WantedBy both
# multi-user.target and suspend.target does not reliably fire on wake;
# /usr/lib/systemd/system-sleep is the documented hook and runs with "post".
install -d /usr/lib/systemd/system-sleep
cat > "$SLEEP" <<'S'
#!/bin/sh
# Restore the keyboard backlight after resume. Called with: pre|post <suspend|hibernate>
[ "$1" = post ] || exit 0
[ -r /etc/default/acer-backlight ] && . /etc/default/acer-backlight
/sbin/modprobe acpi_call 2>/dev/null
exec /usr/local/bin/acer-backlight -b "${BRIGHT:-60}" "${COLOR:-warm}"
S
chmod 755 "$SLEEP"

cat > "$DESK" <<'D'
[Desktop Entry]
Type=Application
Name=Acer Backlight
Comment=Set the RGB keyboard backlight colour and brightness
Exec=/usr/local/bin/acer-backlight-gui
Icon=acer-backlight
Terminal=false
Categories=Settings;HardwareSettings;GTK;
Keywords=keyboard;backlight;rgb;light;colour;color;
D

# The GUI runs as your user, but acer-backlight needs root to write /proc/acpi/call.
# This grants passwordless sudo for that ONE binary and nothing else. acer-backlight
# validates every argument and only ever writes the lighting ACPI function.
if [[ ${SKIP_SUDOERS:-} != 1 ]]; then
    U_NAME=${SUDO_USER:-$USER}
    printf '%s ALL=(root) NOPASSWD: %s\n' "$U_NAME" "$BIN" > "$SUDOD"
    chmod 440 "$SUDOD"
    visudo -cf "$SUDOD" >/dev/null || { rm -f "$SUDOD"; echo "sudoers rule rejected; removed"; exit 1; }
fi

systemctl daemon-reload
systemctl enable acer-backlight.service >/dev/null
systemctl start acer-backlight.service || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf /usr/share/icons/hicolor || true
command -v update-desktop-database >/dev/null && update-desktop-database /usr/share/applications || true

echo "installed."
if ! modprobe acpi_call 2>/dev/null; then
    echo
    echo "  NOTE: acpi_call is present but will not load."
    if [[ $(mokutil --sb-state 2>/dev/null) == *enabled* ]]; then
        echo "  Secure Boot is on and your key is not enrolled yet."
        echo "  Reboot, choose \"Enroll MOK\", and enter the password you set."
    else
        echo "  Try: sudo dkms autoinstall && sudo modprobe acpi_call"
    fi
    echo
fi
"$BIN" detect
echo
echo "Open \"Acer Backlight\" from your app grid, or try:  sudo acer-backlight purple"
echo "If the colours come out wrong on your model:        sudo acer-backlight calibrate"
