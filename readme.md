# alpine_proot.sh — Alpine Linux on Android, the no-root way

> Run a complete **Alpine Linux** system inside **Termux** on any Android phone.
> One small bash file. **No root needed.** Official sources only.
> Optional: a full **LXQt desktop with VNC**, so you can use Linux apps in a window.

![platform](https://img.shields.io/badge/platform-Android-blue)
![shell](https://img.shields.io/badge/shell-bash-green)
![license](https://img.shields.io/badge/license-free--to--use-yellow)
![version](https://img.shields.io/badge/version-1.4.1-orange)

---

## What is this?

`alpine_proot.sh` is a single script that turns Termux into a tiny Alpine
Linux installer. Run it once, and it puts a real Alpine system on your
phone. You then get a root shell inside that system where `apk` (Alpine's
package manager) just works, so you can install almost anything Alpine
offers — editors, compilers, Python, servers, you name it.

It uses **proot**, a program that lets a normal (non-root) app pretend to
be root and use a folder as its own private root directory. Nothing on
Android is modified. No bootloader, no system partition, no warranty-
voiding tricks. When you delete the folder, Alpine is gone — like it
never happened.

Want more than a terminal? The script can also install the **LXQt
desktop** with a **TigerVNC** server inside Alpine. You connect any VNC
viewer app on the same phone and you get a full graphical Linux desktop.

## Why people like it

- **One file.** Copy one script, run it. No git, no curl-pipe-bash chains.
- **No root.** Works on a stock, locked phone through Termux.
- **Official sources only.** The Alpine system comes from Alpine's own
  CDN, and every download is **SHA-256 checksum verified** before use.
- **Small.** The base system is about 15 MB on disk; the download is ~4 MB.
- **Desktop in one pick.** LXQt + TigerVNC install with one menu option,
  with package names verified for every supported CPU architecture.
- **Phone-friendly screens.** Every menu and help page is narrow on
  purpose, so nothing wraps or breaks on small screens or high zoom.
- **Safe to re-run.** Every command checks the current state first and
  never breaks a healthy install.
- **Clean removal.** One option deletes everything Alpine-related.

## Requirements

| You need            | Details                                                      |
|---------------------|--------------------------------------------------------------|
| Android             | 7.0 or newer works best (anything running modern Termux)     |
| Termux              | From **F-Droid** or **GitHub** — not the Play Store build    |
| Architecture        | aarch64, armv7 (32-bit), x86_64, or x86                      |
| Free space          | ~60 MB for the base system, ~1.2 GB if you add the desktop   |
| Internet            | Needed once for the downloads (official mirrors only)        |

## Quick start (3 steps)

1. Put the file on your phone and open Termux in the same folder.
2. Run it — the `+x` permission is optional:

   ```sh
   bash alpine_proot.sh
   ```

3. A menu opens. Pick **1** to install Alpine, wait a minute, then pick
   **2** to step inside. That's it.

If you prefer commands over menus, everything is also a subcommand:

```sh
bash alpine_proot.sh setup          # one-time install
bash alpine_proot.sh shell          # enter Alpine as root
```

## The menu (what the numbers do)

| Pick | Action                        | What it means                                |
|------|-------------------------------|----------------------------------------------|
| 1    | Install Alpine (setup)        | One-time install: engine + Alpine system     |
| 2    | Enter Alpine (shell)          | Root shell inside Alpine, `apk` works        |
| 3    | Install desktop (LXQt + VNC)  | Adds the graphical desktop (big download)    |
| 4    | Start desktop (VNC :1)        | Boots the desktop in the background          |
| 5    | Stop desktop                  | Ends the graphical session, saves battery    |
| 6    | Workspace info                | Version, size, location, desktop state       |
| 7    | Remove Alpine                 | Deletes the whole Alpine installation        |
| 8    | Help                          | The full manual, right in the terminal       |
| 0    | Exit                          | Close the menu                               |

The top of the menu always shows two live status lines: which Alpine
version is installed and whether the desktop is running.

## Commands (for people who like typing)

```sh
bash alpine_proot.sh setup          # install Alpine (alias: set-up)
bash alpine_proot.sh shell          # enter the Alpine root shell
bash alpine_proot.sh desktop-setup  # install LXQt + TigerVNC inside Alpine
bash alpine_proot.sh desktop-start  # start the desktop (VNC 127.0.0.1:5901)
bash alpine_proot.sh desktop-stop   # stop the desktop session
bash alpine_proot.sh info           # what is installed, size, state
bash alpine_proot.sh remove         # delete the Alpine installation
bash alpine_proot.sh --help         # the manual
bash alpine_proot.sh --version      # version info
```

Every subcommand also understands `--help`, so `bash alpine_proot.sh
desktop-setup --help` explains that step in detail.

## The desktop: LXQt + VNC, step by step

The desktop is an optional add-on that lives **inside** Alpine and is
installed with Alpine's own packages (`lxqt-desktop`, `tigervnc`, `dbus`,
`dbus-x11`, `xterm`, `font-dejavu`). Nothing is downloaded from random
websites, and the exact package names were checked against Alpine's live
package index for every supported architecture.

1. **Install it** — menu pick 3 (or `desktop-setup`). This downloads a
   few hundred megabytes, so plug the phone in. It asks you once for a
   **VNC password** (8 characters — that is a VNC limit, not ours).
2. **Start it** — menu pick 4 (or `desktop-start`). The desktop boots in
   the background and keeps running even if you leave the script. A wake
   lock stops Android from freezing it while the screen is off.
3. **Connect** — install any VNC viewer app from your app store (AVNC,
   bVNC and RealVNC Viewer all work). Connect to:

   - address: `127.0.0.1:5901`
   - password: the one you chose in step 1

4. **Stop it** — menu pick 5 (or `desktop-stop`) when you are done. Your
   files stay; only the graphical session closes.

Something looks wrong on the desktop? Check the log at
`~/.proot-alpine/root/.vnc/session.log`, then start it again.

Tip: want a different screen size? Start it with
`PROOT_VNC_GEOM=1920x1080 bash alpine_proot.sh desktop-start`.

## What works inside Alpine

- Full root shell with `apk`, Alpine's package manager (`apk add nano`,
  `apk add python3`, and so on).
- Your phone's shared storage is mounted at `/sdcard`, so files move
  easily between Alpine and Android. If it is not there, run
  `termux-setup-storage` once in Termux and grant the permission.
- Sound, cameras and graphics acceleration are not available — proot has
  no direct hardware access. The VNC desktop renders in software, which
  is fine for file managers, terminals, editors and light apps.

## Safety: where downloads come from

Every byte this script downloads comes from an official source, and it
tells you so while it works:

- `proot`, `tar`, `wget` — installed through **pkg** from Termux's own
  repository (pkg is the only package manager the script touches).
- The Alpine system — from `dl-cdn.alpinelinux.org`, Alpine's official
  CDN, with `mirrors.edge.kernel.org` as an automatic fallback. Both are
  on Alpine's official mirror list.
- A cross-check against `alpinelinux.org/releases.json` makes sure the
  mirror is really serving the current stable release.
- The desktop — from Alpine's own `apk` repositories, inside Alpine.

Each downloaded file is **SHA-256 verified** before it is unpacked. A
corrupted or tampered download is thrown away automatically.

## Where everything lives

| Path                              | What it is                              |
|-----------------------------------|-----------------------------------------|
| `~/.proot-alpine/`                | The whole Alpine system (safe to delete)|
| `~/.proot-alpine/root/.vnc/`      | Desktop session files, logs, password   |
| `~/.proot-alpine/etc/`            | Install receipts (version and arch)     |

Your Termux packages and personal files are never touched by any option
in this script.

## FAQ

**Do I need root?**
No. proot gives the guest system a "fake" root identity that only exists
inside its own folder. Your phone stays locked and untouched.

**Is this the same as Linux Deploy or UserLAnd?**
It is the same idea (a Linux system on Android) but done with one small
readable bash file and only official download sources. There is no app
to install and no account — just Termux and one script.

**How much space does it need?**
The base system is tiny (about 15 MB installed, ~60 MB free needed).
The LXQt desktop is the big one: roughly 1-2 GB including all its
packages. The script checks free space before it starts and warns you
if it is getting tight.

**Which phones does it work on?**
Any phone that runs Termux: aarch64 (most modern phones), armv7 (older
32-bit phones), and x86 / x86_64 (mainly emulators). The script detects
the architecture by itself.

**Why is the desktop slow sometimes?**
The desktop renders in software, and proot adds a little overhead. Close
other Android apps, keep the phone plugged in, and use a smaller VNC
screen size for snappier response.

**Is there sound in the desktop?**
No. VNC carries picture and input only. Apps run fine, but audio is not
part of this setup.

**The shell dies on an old device with a 'seccomp' error. What now?**
Some older kernels cannot run proot's security filter. Start the script
with `PROOT_NO_SECCOMP=1`, for example:
`PROOT_NO_SECCOMP=1 bash alpine_proot.sh shell`

**I already installed with the old `proot.sh` file. Do I need to reinstall?**
No. The new file name is only a name — it uses the exact same
`~/.proot-alpine` folder, so your existing Alpine system keeps working.

**How do I update Alpine?**
Enter the shell (menu pick 2) and run `apk update && apk upgrade`.

**How do I delete everything?**
Menu pick 7, or `bash alpine_proot.sh remove`. It deletes only the
Alpine folder and asks before it does.

## Troubleshooting

| Symptom                              | Fix                                                    |
|--------------------------------------|--------------------------------------------------------|
| `pkg` fails during setup             | Check your internet, then re-run the setup             |
| Checksum mismatch warning            | Nothing to do — the script auto-retries other mirrors  |
| `seccomp` error in the shell         | `PROOT_NO_SECCOMP=1 bash alpine_proot.sh shell`        |
| VNC app cannot connect               | Start the desktop first (pick 4), wait ~10 seconds     |
| VNC connects but screen is black     | Wait a few seconds; check `session.log` (see above)    |
| `/sdcard` missing inside Alpine      | Run `termux-setup-storage` in Termux, then log in again|
| Out of space during desktop install  | Free up storage; the script re-checks on the next run  |

## Removing it completely

Menu pick 7, or:

```sh
bash alpine_proot.sh remove
```

This deletes `~/.proot-alpine` after you confirm. Termux itself and your
other apps stay exactly as they were.

## Help people find this tool (discovery)

If you publish or share this project, these words and tags describe it
well — they are what people actually search for:

**Search keywords:** alpine linux on android, run linux on android
without root, termux alpine installer, proot alpine, linux on phone,
termux no root linux, alpine proot termux, android chroot alternative,
termux desktop environment, lxqt on android, vnc desktop termux,
tigervnc android, proot distro script, alpine minirootfs, single file
bash script, termux linux installer

**Suggested GitHub topics:** `android` `termux` `alpine-linux` `proot`
`lxqt` `vnc` `no-root` `bash` `shell-script` `linux`

**Suggested short description:** "Run Alpine Linux on any Android phone
with Termux — one bash file, no root, official sources only, optional
LXQt + VNC desktop."

## File integrity

- File: `alpine_proot.sh`
- Version: 1.4.1
- Size: 53,993 bytes
- SHA-256: `84bbcaaef1b821a68b31af9bb55dd1fc804d742bb52d89295a1472946cf4dea1`

Check your copy after downloading:

```sh
sha256sum alpine_proot.sh
```

The value must match the one above. If it does, the file is exactly as
published.

## License

Free to use, change and share — no warranty. If it breaks something, the
pieces are yours. (See the note at the top of the script itself.)
