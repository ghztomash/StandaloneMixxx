# Standalone Mixxx

A Raspberry Pi setup for running Mixxx as a standalone DJ deck with a touchscreen and a Pioneer DDJ-FLX controller.

![Preview](./preview.jpg)

Run this command to install Mixxx, configure real-time audio permissions, and set up the controller mappings, LateNightMini skin, and desktop autostart:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ghztomash/StandaloneMixxx/main/install.sh)" -- --bootstrap
```

When the installation finishes, reboot, connect the controller, and log in to the desktop. The launcher starts Mixxx when it detects a `DDJFLX` audio device.

The install command does not run `provision.sh`. That cleanup step is optional and described later.

## What Gets Installed

- [Mixxx](https://mixxx.org/) from Raspberry Pi OS packages by default.
- An optional [my custom 2.7 Mixxx build](https://github.com/ghztomash/mixxx) with stems, additional Rekordbox support and controller fixes.
- [FLX-Mixxx controller mappings](https://github.com/ghztomash/FLX-Mixxx) for DDJ-FLX controllers.
- [LateNightMini skin](https://github.com/ghztomash/LateNightMini), made for small touch displays.
- Desktop autostart using `mixxx-launcher.sh`.

Links to specific component repos:

- Custom Mixxx build: <https://github.com/ghztomash/mixxx>
- LateNightMini skin: <https://github.com/ghztomash/LateNightMini>
- FLX controller mappings: <https://github.com/ghztomash/FLX-Mixxx>

After installation, select `LateNightMini` under Preferences > Interface. Under Preferences > Controllers, select `Pioneer DDJ-FLX2-ghz` or `Pioneer DDJ-FLX4-ghz` for your controller.

## Custom Mixxx Build

To use my custom Mixxx build instead of the vanilla package:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ghztomash/StandaloneMixxx/main/install.sh)" -- --bootstrap --custom
```

This downloads the latest `.deb` build from [my releases](https://github.com/ghztomash/mixxx/releases) and installs it with apt.

The custom build adds or improves:

- Rekordbox library waveform overviews
- Rekordbox library cover art
- Highlighting loaded tracks
- Marking played tracks
- Jog wheel response fixes
- Ability to quit full screen Mixxx without a keyboard

## Tested Setup

- Raspberry Pi 5 and Pi 4B with 4 GB RAM
- Raspberry Pi OS Desktop based on Debian 13 Trixie
- Pimoroni HyperPixel 4.0 touch display
- Pioneer DJ DDJ-FLX4 and DDJ-FLX2 controllers
- Mixxx from Raspberry Pi OS packages or my custom `.deb`

Other Raspberry Pi models and controllers may work, but are not tested here.

## Install Command Examples

The bootstrap command clones this repository into:

```text
~/.local/share/standalone-mixxx/StandaloneMixxx
```

It then runs `install.sh` from that checkout. Run the command again to update the installer, skin, and controller mappings.

### Install only specific components

Install all components with the Raspberry Pi OS Mixxx package:

```sh
./install.sh
```

Install all components with the custom Mixxx build:

```sh
./install.sh --custom
```

Install or update only the controller mappings:

```sh
./install.sh --controllers
```

Install or update only the LateNightMini skin:

```sh
./install.sh --skin
```

Install only Mixxx:

```sh
./install.sh --mixxx
```

Install only real-time audio permissions:

```sh
./install.sh --realtime
```

Install only desktop autostart:

```sh
./install.sh --autostart
```

Options can be combined:

```sh
./install.sh --controllers --skin
./install.sh --mixxx --custom
```

## Updates

Rerun the installer to update the components it manages.

For the bootstrap:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ghztomash/StandaloneMixxx/main/install.sh)" -- --bootstrap
```

Or in the local checkout:

```sh
./install.sh
```

The installer updates clean Git checkouts with `git fetch` and a fast-forward merge. If a checkout contains local changes, it stops without overwriting them.

Mixxx package updates use apt. With `--custom`, the installer checks the latest GitHub release and downloads the matching `.deb`.

## Uninstall

Remove the managed skin link, controller links, desktop autostart entry, and clean controller and skin checkouts:

```sh
./install.sh --remove
```

Remove only one managed part:

```sh
./install.sh --controllers --remove
./install.sh --skin --remove
./install.sh --autostart --remove
```

The script does not remove the Mixxx package or undo the system-wide real-time audio settings. To remove Mixxx, use apt:

```sh
sudo apt remove mixxx
```

For real-time audio settings, check:

```text
/etc/security/limits.d/95-audio.conf
```

## Default Paths

Managed checkouts:

```text
~/.local/share/standalone-mixxx/StandaloneMixxx
~/.local/share/standalone-mixxx/FLX-Mixxx
~/.local/share/standalone-mixxx/LateNightMini
```

Mixxx user files:

```text
~/.mixxx/controllers
~/.mixxx/skins/LateNightMini
~/.mixxx/mixxx_launcher.log
```

Desktop autostart:

```text
~/.config/autostart/mixxx.desktop
```

Custom Mixxx downloads:

```text
~/.cache/standalone-mixxx
```

System real-time audio limits:

```text
/etc/security/limits.d/95-audio.conf
```

## Hardware

Recommended hardware:

- [Raspberry Pi 5](https://www.raspberrypi.com/products/raspberry-pi-5/?variant=raspberry-pi-5-4gb), tested with 4 GB RAM.
- [Raspberry Pi USB-C power supply](https://www.raspberrypi.com/products/27w-power-supply/) with enough current for the controller.
- Fast microSD card, 16 GB or larger.
- Touch display such as the [Pimoroni HyperPixel 4.0](https://shop.pimoroni.com/products/hyperpixel-4?variant=12569485443155), with a resolution of at least 800x480.
- [Pioneer DJ DDJ-FLX4](https://www.pioneerdj.com/en/product/dj-controllers/ddj-flx4/) or DDJ-FLX2.
- Mouse and keyboard for first setup.

## Operating System

Install Raspberry Pi OS with [Raspberry Pi Imager](https://www.raspberrypi.com/documentation/computers/getting-started.html#raspberry-pi-imager).

This setup is tested on Raspberry Pi OS Desktop based on Debian Trixie. Raspberry Pi OS Lite may work, but requires a separately installed and configured desktop environment.

For an alternative preconfigured system, see the [mixxx-pi-gen image](https://github.com/fayaaz/mixxx-pi-gen). It uses Sway and includes Mixxx 2.4. You can install my custom Mixxx 2.7 build, controller mappings, and skin on top:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ghztomash/StandaloneMixxx/main/install.sh)" -- --bootstrap --mixxx --controllers --skin --custom
```

There is no need to add `--autostart` as the image starts Mixxx through Sway.

## Display Notes

Follow your display vendor's setup guide.

For the Pimoroni HyperPixel 4.0, this overlay may be needed in `/boot/firmware/config.txt`:

```ini
dtoverlay=vc4-kms-dpi-hyperpixel4
```

If the display needs I2C disabled:

```sh
sudo raspi-config nonint do_i2c 1
```

Rotate the display from Raspberry Pi OS:

```text
Preferences -> Control Centre -> Screens
```

If boot gets stuck waiting for `renderD128`, inspect LightDM:

```sh
systemctl cat lightdm
sudo systemctl edit lightdm
```

One possible override is:

```ini
[Unit]
After=
After=systemd-user-sessions.service dev-dri-card0.device
Wants=
Wants=dev-dri-card0.device
```

Compare the override with the output of `systemctl cat lightdm` before saving it. Preserve any other entries required by the installed unit, then reload systemd:

```sh
sudo systemctl daemon-reload
```

## Provisioning

The optional `provision.sh` script removes selected desktop extras, disables unused services, updates packages, and prints diagnostics. Use it optionally on a fresh Raspberry Pi OS Desktop installation.

```sh
./provision.sh
```

Run only part of it:

```sh
./provision.sh --updates
./provision.sh --packages
./provision.sh --services
./provision.sh --report
```

Reboot after package or service cleanup:

```sh
sudo reboot
```

The default provisioning run is aggressive enough for a dedicated Mixxx appliance. It does not change display overlays, boot command line, USB tuning, or real-time audio limits.

## Manual Real-Time Audio Setup

The installer handles this automatically during a full install or with:

```sh
./install.sh --realtime
```

Manual equivalent:

```sh
sudo usermod -aG audio "$USER"
sudo editor /etc/security/limits.d/95-audio.conf
```

Add:

```text
@audio - rtprio 95
@audio - memlock unlimited
@audio - nice -19
```

Reboot, then check:

```sh
groups
ulimit -r
ulimit -l
```

## Building Mixxx From Source

Most people should use `./install.sh --custom` instead. Build from source only if you want to change Mixxx itself.

```sh
git clone https://github.com/ghztomash/mixxx.git
cd mixxx
git checkout rekordbox-fixes-integration

./tools/debian_buildenv.sh setup
mkdir build
cd build
cmake ..
cmake --build . --parallel "$(nproc)"
```

Building on the Raspberry Pi can take a long time. A Raspberry Pi with at least 4 GB RAM is recommended for building. See the official Mixxx [developer documentation](https://github.com/mixxxdj/mixxx/blob/main/CONTRIBUTING.md) for more detail.

## Acknowledgments

For more inspiration, check out:

- [Pioneered](https://github.com/timewasternl/Pioneered)
- [XDJ100SX](https://github.com/marcmonka/XDJ100SX)
- [mixxx-pi-gen](https://github.com/fayaaz/mixxx-pi-gen)
- [mixxx-pi-config](https://github.com/EmperorJack/mixxx-pi-config)
- [foss-dj-player](https://github.com/fibonacid/foss-dj-player)
