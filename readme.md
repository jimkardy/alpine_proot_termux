# proot.sh — Alpine Linux on Android, the no-root way

> Run a complete **Alpine Linux** system inside **Termux** on any Android phone.
> One small bash file. **No root needed.** Official sources only.
> Optional: a full **LXQt desktop with VNC**, so you can use Linux apps in a window.

![platform](https://img.shields.io/badge/platform-Android-blue)
![shell](https://img.shields.io/badge/shell-bash-green)
![license](https://img.shields.io/badge/license-free--to--use-yellow)
![version](https://img.shields.io/badge/version-1.4.1-orange)

---

## one linear installation method
``` bash
curl -sSL -o proot.sh https://github.com/jimkardy/alpine_proot_termux/releases/latest/download/proot.sh && chmod +x proot.sh && ./proot.sh

```

## What is this?

`proot.sh` is a single script that turns Termux into a tiny Alpine
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
