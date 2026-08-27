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

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

if [[ ${1:-install} == uninstall ]]; then
    systemctl disable --now acer-backlight.service 2>/dev/null || true
    rm -f "$BIN" "$GUI" "$UNIT" "$MODC" "$CONF" "$SUDOD" "$DESK" "$ICON" /etc/acer-backlight.conf
    systemctl daemon-reload
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf /usr/share/icons/hicolor || true
    echo "removed."
    exit 0
fi

# --- dependency check -----------------------------------------------------
miss=()
python3 -c "import gi; gi.require_version('Gtk','4.0'); gi.require_version('Adw','1')" 2>/dev/null \
    || miss+=("python3-gi gir1.2-gtk-4.0 gir1.2-adw-1")
modinfo acpi_call >/dev/null 2>&1 || miss+=("acpi-call-dkms")
if (( ${#miss[@]} )); then
    echo "Missing dependencies. Install them first:"
    echo "    sudo apt install ${miss[*]}"
    echo
    [[ " ${miss[*]} " == *acpi-call-dkms* ]] && cat <<'N'
NOTE: if Secure Boot is enabled, acpi-call-dkms asks you to set a one-time
password during install. Reboot afterwards and choose "Enroll MOK" on the
blue screen, entering that password. Without it the module cannot load.
Check with: mokutil --sb-state
N
    exit 1
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
WantedBy=multi-user.target suspend.target hibernate.target suspend-then-hibernate.target
U

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
"$BIN" detect
echo
echo "Open \"Acer Backlight\" from your app grid, or try:  sudo acer-backlight purple"
echo "If the colours come out wrong on your model:        sudo acer-backlight calibrate"
