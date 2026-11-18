<h1 align="center">wayscriber-numpad</h1>

<p align="center">
  <strong>Draw on your screen and switch pens with the number pad.</strong><br>
  Screen annotation for recordings on KDE Plasma (Wayland).
</p>


---


<p align="center">
  <img src="https://raw.githubusercontent.com/MarcusHoltz/marcusholtz.github.io/refs/heads/main/assets/img/header/header--wayscriber--desktop-whiteboard-write-on-screen-keyboard-keypad-shortcut.jpg" alt="wayscriber-numpad header banner: writing on the desktop with number pad shortcuts">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/built%20for-KDE%20Plasma%20Wayland-1d99f3" alt="Built for KDE Plasma Wayland">
  <img src="https://img.shields.io/badge/Supported%20on-Arch%20%7C%20Debian%2013%2B%20%7C%20Ubuntu%2025.10%2B%20%7C%20Fedora-blue" alt="Supported distros">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License: MIT">
</p>

<p align="center">
  <a href="#-install">Install</a> ·
  <a href="#-usage">Usage</a> ·
  <a href="#number-pad-keys">Keys</a> ·
  <a href="#-customize-the-tools">Customize</a> ·
  <a href="#-troubleshooting">Troubleshooting</a> ·
  <a href="#-reference">Reference</a>
</p>


---


## 👍 Overview

Turn on **Drawing Mode** from the app menu, press **1** on the number pad,
and draw over anything on screen. The other number pad keys pick a pen,
highlighter or eraser, and undo, redo or clear. Press **1** again to get
back to your apps. Turn Drawing Mode off and the number pad types numbers
again.

Two upstream projects do the work:

- **[wayscriber](https://github.com/devmobasa/wayscriber)** draws. It is a
  native Wayland annotation tool.
- **[keyd](https://github.com/rvaiya/keyd)** connects the number pad to
  wayscriber.

This repo is one script, `wayscriber.sh`. It builds, installs and wires up
both, and removes its own changes again on uninstall.


* * *


## ✅ Requirements

- **A supported Linux distribution:**
  - Arch, or an Arch-based distro (Manjaro, CachyOS, ...)
  - Debian 13 or newer
  - Ubuntu 25.10 or newer, including 26.04 LTS. Ubuntu 24.04 is too old: it
    has no keyd or gtk4-layer-shell package.
  - Fedora
- **KDE Plasma in a Wayland session.** Check with `echo $XDG_SESSION_TYPE`.
  It must print `wayland`. If it prints `x11`, log out and pick
  **Plasma (Wayland)** on the login screen.
- **A keyboard with a number pad.**
- **Docker with Docker Compose.** Check with `docker compose version`.
  wayscriber is not in any distro's official repos, so it is compiled in a
  throwaway Docker container. Nothing is compiled on your system.
- **sudo access.** Used during install for keyd and system packages.

> [!NOTE]
> Tested: install, `status` and `uninstall` were run end to end on
> Ubuntu 26.04 LTS in a container. A container has no desktop, so drawing
> itself was not tested there.


* * *


## 🚀 Install

```bash
git clone https://github.com/MarcusHoltz/wayscriber-numpad.git
cd wayscriber-numpad
./wayscriber.sh install
```

Run it as your normal user, from a terminal inside your Plasma session.
It asks for sudo itself where needed, and refuses to run as root or from
`su`, `sudo` or `ssh`.

Install lists every step it will take and asks before doing anything. To
see the list without changing anything:

```bash
./wayscriber.sh install --dry-run
```

The first install compiles wayscriber, which takes several minutes.

> [!IMPORTANT]
> When install finishes, **log out and back in** once. Install adds you to
> the `keyd` group, and that only takes effect on a new login.


* * *


## 📖 Usage


### Drawing Mode

1. Open the app menu, type **Drawing Mode** and click it. A popup confirms
   it is on, and the wayscriber icon appears in the system tray.
2. Press **1** on the number pad to show the drawing layer. Draw with the
   mouse.
3. Press **1** again to hide the drawing layer and use your apps normally.
4. Click **Drawing Mode** again to turn it off.

- **Keep Num Lock on.** With Num Lock off, the tool keys send arrow keys
  instead of digits and do nothing.
- Right-click **Drawing Mode** in the menu for **Turn On** and
  **Turn Off**, or to pin it to the panel.
- Drawing Mode never starts on its own, and turns off when you log out.


* * *


### Number pad keys

```text
  ┌────────┬────────┬────────┐
  │   7    │   8    │   9    │
  │ clear  │ light  │  red   │
  ├────────┼────────┼────────┤
  │   4    │   5    │   6    │
  │  dark  │ hilite │ eraser │
  ├────────┼────────┼────────┤
  │   1    │   2    │   3    │
  │  draw  │  undo  │  redo  │
  ├────────┴────────┼────────┤
  │        0        │   .    │
  │      blue       │        │
  └─────────────────┴────────┘
```

| Key | Action |
|-----|--------|
| 1 | Show or hide the drawing layer |
| 2 | Undo |
| 3 | Redo |
| 4 | Dark pen (`#222222`, size 3) |
| 5 | Yellow highlighter (`#FFFF00`, size 20, see-through) |
| 6 | Eraser (size 50) |
| 7 | Clear the screen |
| 8 | Light passthrough: ink dims and clicks go to the app underneath |
| 9 | Red pen (`#FF0000`, size 5), the default |
| 0 | Blue pen (`#0000FF`, size 5) |

- A tool stays selected until you pick another.
- Keys 1 and 8 work whenever Drawing Mode is on.
- Keys 2-7, 9 and 0 only act while the drawing layer is showing.
- With Drawing Mode off, every number pad key types its normal digit.


* * *


### From a terminal

Run these from the `wayscriber-numpad` folder:

```bash
./wayscriber.sh start      # turn Drawing Mode on
./wayscriber.sh stop       # turn Drawing Mode off
./wayscriber.sh status     # check what is installed and running
./wayscriber.sh update     # rebuild wayscriber from the latest upstream source
./wayscriber.sh uninstall  # remove everything install added
./wayscriber.sh help       # command list and key map
./wayscriber.sh            # menu
```

| Command | Also accepted |
|---------|---------------|
| `start` | `on`, `enable` |
| `stop` | `off`, `disable` |
| `install` | `setup` |
| `update` | `upgrade` |
| `uninstall` | `remove` |


* * *


## 🎨 Customize the tools


### Pens, colors and sizes

Tools live in this repo's `config.toml`:

- `[presets.slot_1]` to `[presets.slot_5]` are the tools on keys 9, 0, 4, 5
  and 6, in that order.
- `[keybindings]` sets which key does what: undo, redo, clear and the
  tools.

After editing, run `./wayscriber.sh install` again. It copies the file to
`~/.config/wayscriber/config.toml`, and restarts Drawing Mode if it is on.

> [!WARNING]
> This repo's `config.toml` always wins. Edits made directly to
> `~/.config/wayscriber/config.toml` are replaced on the next install. The
> replaced copy is saved to
> `~/.local/state/wayscriber-numpad/config-backups/` first.

Every available setting is listed in wayscriber's
[`config.example.toml`](https://github.com/devmobasa/wayscriber/blob/main/config.example.toml).


* * *


### Highlighter see-through level

`marker_opacity` in `[presets.slot_4]`. Range 0.05 (faint) to 0.90 (solid).
This repo uses 0.15.


* * *


### On-screen extras

Off, for clean recordings. `config.toml` turns off wayscriber's status bar,
zoom chip, page badge, tips and toasts. Set any of them to `true` to bring
it back.

While drawing, **F12** or **F4** shows the status bar until Drawing Mode is
turned off.


* * *


### On/off popups

Drawing Mode shows a popup when it turns on or off, or fails to start. To
silence them, set `POPUPS=false` near the top of
`~/.local/bin/wayscriber-numpad`. Install never overwrites that file once it
exists, so the change stays.

The popups need the `notify-send` command, which install does not add. If
no popups appear, install it: `libnotify-bin` on Debian and Ubuntu,
`libnotify` on Arch and Fedora. Drawing Mode works without it.


* * *


## 🔄 Update

```bash
./wayscriber.sh update
```

Rebuilds wayscriber from its latest upstream source and replaces the
installed copy. The new version is used the next time Drawing Mode turns
on.


* * *


## 🧹 Uninstall

```bash
./wayscriber.sh uninstall
```

Asks first, then turns Drawing Mode off and removes the Drawing Mode app,
the keyd config and the helper script. If install enabled the keyd service
or added you to the `keyd` group, those are undone too. A keyd setup you had
before installing is left alone.

These stay installed. Uninstall prints the commands to remove them:

- The keyd package (Arch, Debian, Ubuntu). On Fedora, the keyd files
  install built from source are removed.
- wayscriber and its runtime libraries, in case you use wayscriber on its
  own.

On Debian and Ubuntu, the keyd service stays enabled after uninstall. The
keyd package enables it by itself, so install never did. With the config
removed it changes no keys. To turn it off:

```bash
sudo systemctl disable --now keyd
```


* * *


## 🔨 Troubleshooting

Start with `./wayscriber.sh status`. It checks each piece and says what is
missing.


* * *


### "Drawing Mode didn't start"

The popup, or `./wayscriber.sh start`, gives the reason. Nothing was
changed, and the number pad still types numbers. Usual causes:

- You are in an X11 session. Log out and pick **Plasma (Wayland)**.
- You haven't logged out and back in since install.
- Another copy of wayscriber is already running. Close it first.
- keyd isn't running. Restarting the computer usually fixes it.

Full log:

```bash
journalctl --user -u wayscriber-numpad.service -n 30
```


* * *


### Number pad keys do nothing

- Check that Num Lock is on.
- Press **1** first. Most keys only act while the drawing layer shows.
- Run `sudo keyd monitor` and press the keys. It should print `kp0` to
  `kp9`. If it doesn't, keyd can't see your keyboard.


* * *


### The drawing layer looks blurry

KDE's "Better Blur DX" effect blurs it. The fix is in wayscriber's
troubleshooting docs:
[Overlay is blurry/non-transparent on KDE Plasma](https://github.com/devmobasa/wayscriber#overlay-is-blurrynon-transparent-on-kde-plasma).


* * *


### Tray menu "Configure" says "Configurator not found"

Harmless. This setup doesn't install wayscriber's separate settings app, so
it opens `~/.config/wayscriber/config.toml` in your text editor instead.


* * *


### Fedora: keyd blocked by SELinux

Check the audit log:

```bash
sudo ausearch -m avc -ts recent
```


* * *


## 📚 Reference

None of this is needed to use it.


### How it works

- **Drawing Mode** is a systemd user service,
  `~/.config/systemd/user/wayscriber-numpad.service`. Turning it on starts
  `wayscriber --daemon` and binds number pad keys 1 and 8 with `keyd bind`.
  Turning it off, a crash, or logging out stops wayscriber and runs
  `keyd bind reset`, so the number pad is never left remapped. The service
  is not enabled, so it never starts on its own.
- **The app menu entry** runs `~/.local/bin/wayscriber-numpad`, the on/off
  switch for that service.
- **Keys 1 and 8** go through keyd, because they must work while the
  drawing layer is hidden. keyd runs as root, so it calls
  `~/.local/bin/wayscriber-ctl.sh`, which runs wayscriber as you.
- **Keys 2-7, 9 and 0** are not touched by keyd. While the drawing layer
  shows, wayscriber has the keyboard and reads them through the
  `[keybindings]` in `config.toml`. wayscriber has no command-line way to
  trigger undo, redo or tool changes, so this is the only way to bind them.
- **The build.** `Dockerfile` compiles wayscriber on Debian 13
  (glibc 2.41). One binary runs on every supported distro, since they all
  have glibc 2.41 or newer. Only the finished binary leaves the container,
  into `dist/`. Fedora has no keyd package, so keyd v2.6.0 is compiled in
  the same container and installed with `make install`.
- **Packages.** Everything else comes from your distro's official repos.
  No AUR, PPAs or third-party repos. Debian and Ubuntu name the keyd
  command `keyd.rvaiya`. The script handles that.
- **Receipt.** Install records what it changed in
  `~/.local/state/wayscriber-numpad/`, so uninstall only undoes its own
  work.


* * *


### What install changes

| Where | What | sudo |
|---|---|---|
| keyd | Installed from the distro repo (built from source on Fedora), service enabled, you added to the `keyd` group | yes |
| `/etc/keyd/wayscriber.conf` | keyd config, no permanent remaps | yes |
| System packages | wayscriber's runtime libraries (cairo, pango, gtk4, gtk4-layer-shell, libadwaita, ...) and the screenshot helpers wl-clipboard, grim, slurp | yes |
| `~/.local/bin/wayscriber` | The wayscriber program | no |
| `~/.config/wayscriber/config.toml` | Tool presets and key bindings | no |
| `~/.local/bin/wayscriber-ctl.sh` | Helper keyd uses to run wayscriber as you | no |
| `~/.local/bin/wayscriber-numpad` | Drawing Mode on/off switch | no |
| `~/.config/systemd/user/wayscriber-numpad.service` | Drawing Mode service (not enabled) | no |
| `~/.local/share/applications/wayscriber-numpad.desktop` | Drawing Mode app menu entry | no |


* * *


### Upstream projects

- wayscriber source and docs: https://github.com/devmobasa/wayscriber
- wayscriber website: https://wayscriber.com
- wayscriber Q&A wiki: https://deepwiki.com/devmobasa/wayscriber
- keyd: https://github.com/rvaiya/keyd


* * *


## 📜 License

MIT, see [LICENSE](LICENSE). wayscriber and keyd are separate projects under
their own licenses.
