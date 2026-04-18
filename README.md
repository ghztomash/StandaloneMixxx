# Standalone Mixxx

This is a short guide how to set up Mixxx on a Rasberry Pi to act as a standalone DJ deck with a MIDI controller like DDJFLX4.

This guide is focused on a Rasberry Pi 5 4GB with a Pimoroni Hyperpixel 4.0 touch display, DDJ-FLX4 and Rasbian OS based on Debian 13 Trixie. But any combination should in theory work but your millage may vary.

## Hardware

Hardware necessary for this project:

- [Rasberry Pi 5 with 4 GB RAM](https://www.raspberrypi.com/products/raspberry-pi-5/?variant=raspberry-pi-5-4gb), but 2 GB should be sufficient specially if you don't intend to build Mixxx from source (not tested).
- [Raspberry Pi USB-C power supply](https://www.raspberrypi.com/products/27w-power-supply/), rated for least 5.0A output current, depending on your MIDI controller needs too.
- [microSD card](https://www.sandisk.com/en-gb/products/memory-cards/microsd-cards/sandisk-extreme-pro-uhs-i-microsd?sku=SDSQXCG-032G-GN6MA) at least 16 GB or more, specially if you wish to record your mixes or build from source. Choose the highest quality and read/write speeds for faster boot time.
- Touch display like [Pimoroni HyperPixel 4.0](https://shop.pimoroni.com/products/hyperpixel-4?variant=12569485443155). With resolution 800x480 or higher.
- [DJ controller](https://www.pioneerdj.com/en/product/dj-controllers/ddj-flx4/) with built in audio interface, like Pioneer DJ DDJ-FLX4 or DDJ-FLX2.
- Mouse & Keyboard is helpful for the initial configuration.

## Operating System

Install the operating system using [pi-imager](https://www.raspberrypi.com/documentation/computers/getting-started.html#raspberry-pi-imager) onto the microSD card.

I chose to go with the standard Rasberry Pi OS Desktop based on the latest Debian Trixie. And then remove the unnecessary desktop components.

You may choose to go with Rasberry Pi OS Lite and then install only the necessary components, this way you should have a "leaner" system.

In the future I might look into providing ready built and configured images.

### Configure the OS

After the fresh installation update and configure your operating system

```sh
sudo apt update  

# Remove any unwanted software
sudo apt remove -y rpi-connect cloud-init chromium cups geany thonny agnostics rpi-imager piclone rp-bookshelf rp-prefapps rpi-userguide rpinters

# Update the remaining software
sudo apt full-upgrade -y

# Clean up
sudo apt autoremove -y
sudo apt autoclean -y

# Do your preference configuration
sudo raspi-config
sudo vim /boot/firmware/config.txt

# Kernel options
sudo vim /boot/firmware/cmdline.txt
```

### Desktop configuration

You can further customize the system to your liking, like disable media pop-ups, UI notifications and hide the mouse. From File explorer Preferences and Control Center preferences. 

### Services

**Optional** - disable any unwanted services that slowdown boot

```sh
# Analyze the source of slowdowns
systemd-analyze blame
systemd-analyze critical-chain

# Disable any unwanted services
sudo systemctl disable NetworkManager-wait-online.service  
sudo systemctl mask NetworkManager-wait-online.service

sudo systemctl disable ModemManager  
sudo systemctl mask ModemManager

sudo systemctl disable bluetooth  
sudo systemctl mask bluetooth
```

This step is probably not necessary if you start with a Lite OS.
And is for more advanced users, as you may break your system by removing the wrong service.

## Display

Follow the installation and configuration guide of your display.

For the Pimoroni Hyperpixel I had to change the `dtoverlay=vc4-kms-dpi-hyperpixel4` in `/boot/firmware/config.txt`

```sh
sudo vim /boot/firmware/config.txt

# disable I2C and GPIO
sudo raspi-config nonint do_i2c 1

# or using 
sudo raspi-config
```

If you need to rotate the display you can do this using the graphical Screen Configuration utility - find it under `Preferences -> Control Centre -> Screens` in Raspberry Pi OS

If boot is getting stuck waiting for `renderD128`

```sh
# check service
systemctl cat lightdm

sudo cp /usr/lib/systemd/system/lightdm.service /etc/systemd/system/lightdm.service
sudo vim /etc/systemd/system/lightdm.service
```

And remove `dev-dri-renderD128.device` in After and Wants

## Install Mixxx

The easiest path is to install vanilla Mixxx.

But if you want additional features that match the expected Rekodbox user experience, you might need to build Mixxx from scratch with my changes applied.

```sh
sudo apt install mixxx

# If some icons are missing from the Mixxx UI
sudo apt install qt6-svg-plugins
```

### Real-Time threads

Mixxx expects to have real time audio threads enabled to reduce latency.

```sh
sudo usermod -aG audio pi
sudo vim /etc/security/limits.d/95-audio.conf
```

And add to `95-audio.conf`

```sh
@audio - rtprio 95  
@audio - memlock unlimited  
@audio - nice -19
```

Check the changes

```sh
sudo reboot

ulimit -r  
ulimit -l
```

### Building mixxx from source

If you would like to have additional features like:
- Rekodbox library waveform overviews
- Rekordbox library cover art
- Highlight loaded tracks
- Mark played tracks
- Fixed jog wheel response

You will need to build Mixxx from [source with my fixes](https://github.com/ghztomash/mixxx/tree/rekordbox-fixes-integration) applied.

You can either cherry pick my commits on top of `main` branch, or build my fork directly.

```sh
git clone https://github.com/ghztomash/mixxx.git
cd mixxx

git checkout rekordbox-fixes-integration
# or 
git checkout rekordbox-pi

# install development tools
./tools/debian_buildenv.sh setup

# build
mkdir build && cd build
cmake ..
cmake --build . --parallel $(nproc)
```

There should now be a `mixxx` executable in the `build` directory that you can run.

Building directly on the Rasberry Pi might take a couple of hours, you might want to look into cross-compiling.

Follow the official Mixxx [developer documentation](https://github.com/mixxxdj/mixxx/blob/main/CONTRIBUTING.md) for more information.

### Skins

Install a skin that is optimized for small touch screens.

![LateNightMini preview](./latenightmini.png)

Like my [LateNightMini](https://github.com/ghztomash/LateNightMini) or the [Pioneered](https://github.com/timewasternl/Pioneered).

```sh
git clone https://github.com/ghztomash/LateNightMini.git ~/.mixxx/skins/LateNightMini
```

Then open Mixxx and select LateNightMini in Preferences > Interface.

### Controller scripts

Mixxx already supports a [lot of controllers](https://manual.mixxx.org/2.5/en/hardware/manuals) out of the box.

But if you want the user experience that follows more closely the Rekordbox workflow, install my FLX controller scripts.

```sh
git clone https://github.com/ghztomash/FLX-Mixxx.git ~/.mixxx/controllers
```

Then open Mixxx and select the DDJ-FLX2 or DDJ-FLX4 device in Preferences -> Controllers. Load the matching mapping named Pioneer DDJ-FLX2-ghz or Pioneer DDJ-FLX4-ghz.

## Auto start

There a launcher script that monitors connected audio devices and launches Mixxx once a controller is connected.

Copy `autostart/mixxx.desktop` to `~/.config/autostart/mixxx.destkop`

Copy `mixxx-launcher.sh` to `~/mixxx-launcher.sh`

Connect and check your controller with `aplay -l`

Edit `mixxx_launcher.sh` and update `DEVICE_NAME="DDJFLX4"` to match your controller.

## Contributors

- [Tomash GHz](https://github.com/ghztomash)

## References

For more inspiration, check out the amazing work of:

- [Pioneered](https://github.com/timewasternl/Pioneered)
- [XDJ100SZ](https://github.com/marcmonka/XDJ100SX)
- https://github.com/fibonacid/foss-dj-player
