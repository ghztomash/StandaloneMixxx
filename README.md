# Standalone Mixxx

A Raspberry Pi setup for running Mixxx as a small standalone DJ deck with a touch screen and a Pioneer FLX controller.

![Preview](./preview.jpg)

The easy path is one command. It installs Mixxx, real-time audio permissions, controller mappings, the LateNightMini skin, and desktop autostart.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ghztomash/StandaloneMixxx/main/install.sh)" -- --bootstrap
```

After it finishes, reboot, plug in the controller, and log in to the desktop. The launcher waits for a `DDJFLX` audio device and starts Mixxx once it appears.

The install command does not run `provision.sh`. That cleanup step is optional and described later.

## What Gets Installed

- [Mixxx](https://mixxx.org/) from Raspberry Pi OS packages by default.
- [My custom Mixxx fork](https://github.com/ghztomash/mixxx), optionally, with extra Rekordbox-oriented fixes.
- [FLX-Mixxx controller mappings](https://github.com/ghztomash/FLX-Mixxx) for DDJ-FLX controllers.
- [LateNightMini skin](https://github.com/ghztomash/LateNightMini), made for small touch displays.
- Desktop autostart using `mixxx-launcher.sh`.

Useful related links:

- Custom Mixxx repo: <https://github.com/ghztomash/mixxx>
- LateNightMini skin: <https://github.com/ghztomash/LateNightMini>
- FLX controller mappings: <https://github.com/ghztomash/FLX-Mixxx>

After installing, open Mixxx and select `LateNightMini` in Preferences > Interface. For the controller, select the DDJ-FLX2 or DDJ-FLX4 mapping named `Pioneer DDJ-FLX2-ghz` or `Pioneer DDJ-FLX4-ghz` in Preferences > Controllers.

## Custom Mixxx Build

To use my custom Mixxx build instead of the normal Raspberry Pi OS package:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ghztomash/StandaloneMixxx/main/install.sh)" -- --bootstrap --custom
```

This downloads the latest `.deb` from [my Mixxx releases](https://github.com/ghztomash/mixxx/releases) and installs it with apt.

The custom build is where I keep fixes and experiments for:

- Rekordbox library waveform overviews
- Rekordbox library cover art
- Highlighting loaded tracks
- Marking played tracks
- Jog wheel response fixes

## Tested Setup

- Raspberry Pi 5 with 4 GB RAM
- Raspberry Pi OS Desktop based on Debian 13 Trixie
- Pimoroni HyperPixel 4.0 touch display
- Pioneer DJ DDJ-FLX4 and DDJ-FLX2 controllers
- Mixxx from Raspberry Pi OS packages or my custom `.deb`

Other Raspberry Pi and controller combinations may work, but this is the setup I test.

## Install Examples

The bootstrap command clones this repository into:

```text
~/.local/share/standalone-mixxx/StandaloneMixxx
```

Then it runs `install.sh` from that checkout. You can rerun the same command later to update the installer, skin, and controller mappings.

Install everything with normal Mixxx:

```sh
./install.sh
```

Install everything with the custom Mixxx build:

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

The selected parts can be combined:

```sh
./install.sh --controllers --skin
./install.sh --mixxx --custom
```

## Updates

Rerun the same install command whenever you want to update the managed pieces.

For the bootstrap install:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ghztomash/StandaloneMixxx/main/install.sh)" -- --bootstrap
```

For a local checkout:

```sh
./install.sh
```

The installer updates clean git checkouts with `git fetch` and a fast-forward merge. If you changed files inside one of those checkouts, it stops instead of overwriting your work.

Mixxx package updates are handled through apt. When Mixxx is selected, the script runs `apt-get update` and installs the needed packages again. For `--custom`, it fetches the latest release metadata from GitHub and downloads the matching `.deb`.

## Uninstall

Remove the managed skin link, controller links, desktop autostart entry, and clean managed checkouts:

```sh
./install.sh --remove
```

Remove only one managed part:

```sh
./install.sh --controllers --remove
./install.sh --skin --remove
./install.sh --autostart --remove
```

The script does not remove the Mixxx package or undo real-time audio settings. That is intentional, because those are system-level changes. If needed, remove Mixxx with apt:

```sh
sudo apt-get remove mixxx
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
- [Raspberry Pi USB-C power supply](https://www.raspberrypi.com/products/27w-power-supply/), with enough current for the controller.
- Fast microSD card, 16 GB or larger.
- Touch display such as [Pimoroni HyperPixel 4.0](https://shop.pimoroni.com/products/hyperpixel-4?variant=12569485443155), 800x480 or bigger.
- [Pioneer DJ DDJ-FLX4](https://www.pioneerdj.com/en/product/dj-controllers/ddj-flx4/) or DDJ-FLX2.
- Mouse and keyboard for first setup.

## Operating System

Install Raspberry Pi OS with [Raspberry Pi Imager](https://www.raspberrypi.com/documentation/computers/getting-started.html#raspberry-pi-imager).

I use Raspberry Pi OS Desktop based on Debian Trixie. Raspberry Pi OS Lite should also work, but you will need to install and configure the desktop parts yourself.

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

Compare this with `systemctl cat lightdm` on your system before saving. Keep any other entries your installed unit needs, then reload systemd:

```sh
sudo systemctl daemon-reload
```

## Provisioning

`provision.sh` is optional. Use it after a fresh Raspberry Pi OS Desktop install if you want to remove desktop extras, disable some unused services, update packages, and print diagnostics.

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

Building on the Raspberry Pi can take a long time. See the official Mixxx [developer documentation](https://github.com/mixxxdj/mixxx/blob/main/CONTRIBUTING.md) for more detail.
