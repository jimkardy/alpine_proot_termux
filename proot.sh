#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#
#   proot.sh -- Alpine Linux on Termux, the effortless (no-root) way
#
#   One file, no dependencies beyond Termux itself. It installs the proot
#   engine, downloads the official Alpine minirootfs straight from Alpine's
#   CDN, verifies its checksum, and drops you into a root shell where apk
#   just works.
#
#   Usage:
#     ./proot.sh                  open the interactive menu (TUI style)
#     ./proot.sh setup            install everything + prepare Alpine (one time)
#     ./proot.sh shell            enter the Alpine shell as root
#     ./proot.sh desktop-setup    add a LXQt desktop + VNC server (optional)
#     ./proot.sh desktop-start    start the desktop (VNC 127.0.0.1:5901)
#     ./proot.sh desktop-stop     stop the desktop session
#     ./proot.sh info             show what is installed and its size
#     ./proot.sh remove           delete the Alpine installation
#     ./proot.sh --help           read the manual
#
#   Everything is downloaded from official sources only:
#     - proot / tar / wget .......... Termux's own package repository
#     - Alpine minirootfs ........... dl-cdn.alpinelinux.org (official CDN),
#                                     fallback: mirrors.edge.kernel.org
#                                     (both are in Alpine's official mirror list)
#     - release cross-check ......... alpinelinux.org/releases.json
#     - LXQt desktop + TigerVNC ..... Alpine's own apk repos (optional,
#                                     installed only if you ask for it)
#
#   Tip: if you do not want to chmod +x the file, just run:
#     bash proot.sh setup
#
# ============================================================================
# This program is free software: do whatever you want with it, it is yours.
# Provided with zero warranty. If it eats your homework, that is on you.
# ============================================================================

# Fail loudly if someone references a variable that was never set.
set -u

VERSION="1.4.0"

# Number of steps the setup walkthrough reports (used by the step headers)
STEP_TOTAL="6"

# ----------------------------------------------------------------------------
# Configuration -- sensible defaults, touch only if you know what you are doing
# ----------------------------------------------------------------------------

# Where the Alpine system will live (hidden folder inside your Termux home)
ROOTFS_DIR="${HOME:-/data/data/com.termux/files/home}/.proot-alpine"

# Standard Termux prefix, used when $PREFIX is not set for some reason
TERMUX_PREFIX_FALLBACK="/data/data/com.termux/files/usr"

# Official Alpine sources
ALPINE_RELEASES_JSON="https://alpinelinux.org/releases.json"
ALPINE_MIRRORS="https://dl-cdn.alpinelinux.org/alpine https://mirrors.edge.kernel.org/alpine"

# DNS servers written into the guest as an offline fallback. On every login
# the host's own resolv.conf is bound on top, so this rarely matters -- but
# if the bind ever fails, apk will still resolve thanks to these.
DNS_FALLBACK="nameserver 1.1.1.1
nameserver 8.8.8.8"

# Optional LXQt desktop, installed INSIDE Alpine from Alpine's own apk
# repositories. These exact package names were verified against the live
# package index of every supported arch (aarch64, armv7, x86, x86_64) --
# Alpine keeps package names identical across architectures.
DESKTOP_PKGS="lxqt-desktop tigervnc dbus dbus-x11 xterm font-dejavu"
DESKTOP_MARKER="$ROOTFS_DIR/etc/.proot-sh-desktop"
VNC_DIR="$ROOTFS_DIR/root/.vnc"      # guest /root/.vnc, seen from Termux
VNC_DISPLAY="1"                      # Xvnc :1  ->  VNC port 5901
VNC_PORT="5901"
VNC_GEOM="${PROOT_VNC_GEOM:-1280x720}"

# ----------------------------------------------------------------------------
# Pretty printing -- degrades to plain text when colors are unavailable
# ----------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_INFO=$'\033[1;34m'   # blue
    C_OK=$'\033[1;32m'     # green
    C_WARN=$'\033[1;33m'   # yellow
    C_BAD=$'\033[1;31m'    # red
else
    C_RESET="" C_BOLD="" C_INFO="" C_OK="" C_WARN="" C_BAD=""
fi

msg()  { printf '%s\n' "  ${C_INFO}[ .. ]${C_RESET} $*"; }
ok()   { printf '%s\n' "  ${C_OK}[ ok ]${C_RESET} $*"; }
warn() { printf '%s\n' "  ${C_WARN}[ !! ]${C_RESET} $*"; }
die()  { stop_spinner; printf '%s\n' "  ${C_BAD}[ XX ]${C_RESET} $*" >&2; exit 1; }
ask()  { printf '%s'   "  ${C_INFO}[ ?? ]${C_RESET} $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# A little card instead of a boring one-liner. Plain ASCII, exactly 26
# columns wide, so it survives any phone screen and any zoom level.
banner() {
    printf '%s\n' "${C_INFO}"
    printf '  +------------------------+\n'
    printf '  |  Alpine Linux - Termux |\n'
    printf '  |  powered by proot.sh   |\n'
    printf '  +------------------------+\n'
    printf '%s  version %s%s%s\n' "${C_RESET}" "${C_BOLD}" "$VERSION" "${C_RESET}"
}

# ----------------------------------------------------------------------------
# Tiny TUI helpers -- a spinning wheel and step headers. Plain bash only, and
# both degrade to ordinary log lines when there is no terminal to draw on.
# ----------------------------------------------------------------------------

SPINNER_PID=""

stop_spinner() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
        printf '\r\033[K'
    fi
}

start_spinner() {
    # No terminal, no colors, no redraw -- then a plain line is kinder.
    if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
        msg "$1"
        return
    fi
    # The wheel needs fractional sleeps; if this system's sleep refuses
    # decimals (some toybox builds do), stay with a plain line.
    if ! sleep 0.1 2>/dev/null; then
        msg "$1"
        return
    fi
    (
        wheel='|/-\\'
        i=0
        while :; do
            i=$(( (i + 1) % 4 ))
            printf '\r  [ %s ] %s  ' "${wheel:$i:1}" "$1"
            sleep 0.12
        done
    ) &
    SPINNER_PID=$!
}

# A short section header, like:  [ 2/6 ] Installing the engine
step() {
    printf '\n%s  [ %s/%s ] %s%s\n' "${C_BOLD}" "$1" "$STEP_TOTAL" "$2" "${C_RESET}"
    printf '%s\n' "  --------------------------------"
}

# Same look, but with a free-form tag for flows that are not part of the
# 6 setup steps (the desktop installer counts its own steps).
dstep() {
    printf '\n%s  [ %s ] %s%s\n' "${C_BOLD}" "$1" "$2" "${C_RESET}"
    printf '%s\n' "  --------------------------------"
}

# ----------------------------------------------------------------------------
# Environment checks
# ----------------------------------------------------------------------------

# Make sure we are actually inside Termux and figure out the prefix.
check_termux() {
    if [ -z "${PREFIX:-}" ] && [ ! -d "$TERMUX_PREFIX_FALLBACK" ]; then
        die "This script is built for Termux (https://termux.dev).
No Termux environment was detected. Install Termux (F-Droid or GitHub
build, NOT the Play Store one), then run this script inside it."
    fi
    PREFIX="${PREFIX:-$TERMUX_PREFIX_FALLBACK}"
    [ -d "$PREFIX" ] || die "Termux prefix '$PREFIX' does not exist."

    local home
    home="${HOME:-$PREFIX/home}"
    [ -d "$home" ] || die "Home directory '$home' does not exist."
    [ -w "$home" ] || die "Home directory '$home' is not writable."
}

# Map the device architecture to Alpine's architecture names.
# dpkg knows best what userspace we run (32-bit Termux on 64-bit phones is
# a thing), uname is only the fallback.
detect_alpine_arch() {
    local raw=""
    if have dpkg; then
        raw="$(dpkg --print-architecture 2>/dev/null || true)"
    fi
    [ -n "$raw" ] || raw="$(uname -m 2>/dev/null || true)"
    [ -n "$raw" ] || die "Could not detect the CPU architecture."

    if [ "$raw" = "aarch64" ]; then
        ALPINE_ARCH="aarch64"
    elif [ "$raw" = "arm" ] || [ "$raw" = "armhf" ] || [ "$raw" = "armv7" ] \
         || [ "$raw" = "armv7l" ] || [ "$raw" = "armv8l" ]; then
        ALPINE_ARCH="armv7"
    elif [ "$raw" = "x86_64" ] || [ "$raw" = "amd64" ]; then
        ALPINE_ARCH="x86_64"
    elif [ "$raw" = "i386" ] || [ "$raw" = "i486" ] || [ "$raw" = "i586" ] \
         || [ "$raw" = "i686" ]; then
        ALPINE_ARCH="x86"
    else
        die "Sorry, Alpine Linux does not ship packages for '$raw'.
This script supports: aarch64, armv7 (32-bit), x86_64 and x86."
    fi
}

# Refuse to start a 100 MB download without something to put it on.
check_disk_space() {
    # Minimum free space in MB: the base system is tiny, the optional
    # desktop needs a lot more room. Callers may pass their own minimum.
    local min_mb="${1:-60}"
    local df_row free_kb free_mb
    # Android's toybox df rejects '-m' on many devices (Termux ships no df
    # of its own), which silently produced an empty reading. Plain POSIX
    # '-P' with 1K-blocks ('-k') works everywhere, and the MB math is done
    # here in bash instead.
    df_row="$(df -Pk "${HOME:-$PREFIX}" 2>/dev/null | tail -n 1)"
    # Column 4 of POSIX df output is the space available. Parsed with pure
    # shell, so even a missing awk cannot break this check.
    set -- ${df_row:-}
    free_kb="${4:-}"
    # Pure-bash "is this a number?" test: strip every digit and see if
    # anything survives. No awk, no case, no external tool involved.
    if [ -z "$free_kb" ] || [ -n "${free_kb//[0-9]/}" ]; then
        warn "Could not determine free disk space, continuing anyway."
        return
    fi
    free_mb=$((free_kb / 1024))
    if [ "$free_mb" -lt "$min_mb" ]; then
        die "Only ${free_mb} MB of free space left. This needs roughly ${min_mb} MB.
Free up some space and try again."
    fi
    if [ "$free_mb" -lt $(( min_mb * 3 )) ]; then
        warn "Only ${free_mb} MB free. It will fit, but it is getting tight."
    fi
}

# ----------------------------------------------------------------------------
# Rootfs helpers
# ----------------------------------------------------------------------------

# A rootfs counts as valid only if the install marker AND the essentials
# are all present. This is what protects us from half-finished setups.
rootfs_is_valid() {
    [ -f "$ROOTFS_DIR/etc/.proot-sh-installed" ] \
        && [ -f "$ROOTFS_DIR/etc/alpine-release" ] \
        && [ -x "$ROOTFS_DIR/bin/busybox" ]
}

rootfs_version() {
    local f="$ROOTFS_DIR/etc/alpine-release" v
    [ -f "$f" ] || return 1
    v="$(< "$f")"
    printf '%s\n' "${v%%$'\n'*}"
}

# --- desktop helpers -------------------------------------------------------

desktop_is_installed() {
    [ -f "$DESKTOP_MARKER" ] && [ -f "$VNC_DIR/start-desktop.sh" ] \
        && [ -f "$VNC_DIR/stop-desktop.sh" ]
}

# Guest processes run under proot WITHOUT a PID namespace, so a pid
# written inside Alpine is a real Termux-side pid -- kill -0 from the
# host just works, which is how we know whether the desktop is up.
desktop_vnc_pid() {
    local f="$VNC_DIR/xvnc.pid" p
    [ -f "$f" ] || return 0
    p="$(< "$f")"
    p="${p//[!0-9]/}"
    if [ -n "$p" ]; then printf '%s\n' "$p"; fi
}

desktop_is_running() {
    local p
    p="$(desktop_vnc_pid)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

# Make sure there is a resolv.conf on the Termux side (proot binds it into
# the guest on every login so that the guest always uses the host's DNS).
ensure_host_resolv() {
    if [ ! -f "$PREFIX/etc/resolv.conf" ]; then
        printf '%s\n' "$DNS_FALLBACK" > "$PREFIX/etc/resolv.conf" 2>/dev/null || true
    fi
}

# Pick the first sha256 utility we can find (coreutils first, busybox second).
sha256_tool() {
    if have sha256sum; then
        echo "sha256sum"
    elif have busybox && busybox sha256sum </dev/null >/dev/null 2>&1; then
        echo "busybox sha256sum"
    else
        echo ""
    fi
}

# ----------------------------------------------------------------------------
# Downloading -- resolve the latest official minirootfs, fetch, verify
# ----------------------------------------------------------------------------

# Resolve + download + checksum-verify the latest minirootfs for $ALPINE_ARCH.
# Tries every official mirror in order; the first one that fully passes wins.
#   Sets:  ALPINE_FILE  (official tarball filename)
#          ALPINE_VER   (e.g. 3.24.2)
#   Expects $WORK_DIR to exist and be empty.
fetch_release() {
    local sha_cmd
    sha_cmd="$(sha256_tool)"
    [ -n "$sha_cmd" ] || die "Neither 'sha256sum' nor busybox was found.
Install it with:  pkg install coreutils"

    # Alpine marks the current stable branch in releases.json; we use it to
    # sanity-check whatever the mirror listing gives us. If alpinelinux.org
    # is unreachable, the listing alone is still authoritative.
    local expected_branch
    expected_branch="$(wget -q -T 15 -O - "$ALPINE_RELEASES_JSON" 2>/dev/null \
        | grep -o '"latest_stable":"[^"]*"' | head -n 1 | sed 's/.*:"v//;s/"$//')"

    local base idx listing file sorted
    for base in $ALPINE_MIRRORS; do
        idx="$base/latest-stable/releases/$ALPINE_ARCH/"
        msg "Looking up the latest Alpine release on ${base#https://} ..."
        listing="$(wget -q -T 20 -O - "$idx")" || {
            warn "Mirror unreachable, trying the next one."; continue
        }

        # Pull every "alpine-minirootfs-<ver>-<arch>.tar.gz" out of the index.
        # The [0-9.]* class naturally skips _rc1/_rc2 release candidates, and
        # sort -V leaves the newest real release at the bottom. Older sort
        # implementations without -V fall back to plain sorting.
        file="$(printf '%s\n' "$listing" \
            | grep -o "alpine-minirootfs-[0-9.]*-${ALPINE_ARCH}\.tar\.gz" \
            | sort -uV 2>/dev/null | tail -n 1)"
        if [ -z "$file" ]; then
            file="$(printf '%s\n' "$listing" \
                | grep -o "alpine-minirootfs-[0-9.]*-${ALPINE_ARCH}\.tar\.gz" \
                | sort -u | tail -n 1)"
        fi

        if [ -z "$file" ]; then
            warn "No minirootfs found on this mirror, trying the next one."
            continue
        fi
        ALPINE_FILE="$file"
        ALPINE_VER="${file#alpine-minirootfs-}"; ALPINE_VER="${ALPINE_VER%%-*}"

        # Soft cross-check against the official branch announcement
        if [ -n "$expected_branch" ] && [ "${ALPINE_VER%.*}" != "$expected_branch" ]; then
            warn "Mirror serves $ALPINE_VER but alpinelinux.org says stable is $expected_branch."
        fi

        msg "Downloading ${ALPINE_FILE} ..."
        if ! wget -c -T 30 -t 3 -q --show-progress -O "$WORK_DIR/$ALPINE_FILE" \
                "$idx$ALPINE_FILE"; then
            warn "Download failed, trying the next mirror."
            rm -f "$WORK_DIR/$ALPINE_FILE"
            continue
        fi

        msg "Downloading the SHA-256 checksum ..."
        if ! wget -q -T 30 -t 3 -O "$WORK_DIR/$ALPINE_FILE.sha256" \
                "$idx$ALPINE_FILE.sha256"; then
            warn "Could not fetch the checksum, trying the next mirror."
            rm -f "$WORK_DIR/$ALPINE_FILE" "$WORK_DIR/$ALPINE_FILE.sha256"
            continue
        fi

        msg "Verifying the download (this catches corrupted files) ..."
        local expected actual
        read -r expected _ < "$WORK_DIR/$ALPINE_FILE.sha256"
        actual="$($sha_cmd "$WORK_DIR/$ALPINE_FILE")"
        actual="${actual%%[[:space:]]*}"
        if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
            warn "Checksum mismatch! The download is corrupt or tampered with."
            rm -f "$WORK_DIR/$ALPINE_FILE" "$WORK_DIR/$ALPINE_FILE.sha256"
            continue
        fi
        ok "Checksum verified."
        return 0
    done
    return 1
}

# ----------------------------------------------------------------------------
# setup -- install the engine, fetch Alpine, get everything ready
# ----------------------------------------------------------------------------

usage_setup() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh setup

${C_BOLD}WHAT IT DOES${C_RESET}
  One-time preparation:

  1. installs the 'proot', 'tar' and 'wget'
     packages through pkg
  2. downloads the latest official Alpine
     minirootfs for this device from Alpine's
     own CDN (checksum-verified, about 4 MB)
  3. unpacks it into ~/.proot-alpine (a
     hidden folder in your Termux home) and
     gets everything ready

  It never enters the Alpine shell by
  itself. When it finishes, run:
  ./proot.sh shell

  Safe to re-run: if Alpine is already set
  up and healthy, it does nothing.

  From the interactive menu, setup offers to
  take you straight inside when it is done.
EOF
}

cmd_setup() {
    banner
    step 1 "Checking your device"
    check_termux
    detect_alpine_arch
    ok "Detected architecture: ${ALPINE_ARCH}"

    # Fast path: nothing to do if Alpine is already healthy.
    if rootfs_is_valid; then
        ok "Alpine $(rootfs_version) is already set up at $ROOTFS_DIR"
        msg "Enter it with: ${C_BOLD}./proot.sh shell${C_RESET}"
        exit 0
    fi
    if [ -e "$ROOTFS_DIR" ]; then
        warn "Found a broken or half-finished install, it will be rebuilt."
        rm -rf "$ROOTFS_DIR"
    fi

    check_disk_space

    # Everything below lands in a temp dir that cleans up after itself,
    # even if you Ctrl-C mid-download.
    WORK_DIR="$(mktemp -d "${TMPDIR:-$HOME}/.proot-setup.XXXXXX")" \
        || die "Could not create a temporary directory."
    trap 'rm -rf "$WORK_DIR"' EXIT
    trap 'stop_spinner; rm -rf "$WORK_DIR"; exit 130' INT
    trap 'stop_spinner; rm -rf "$WORK_DIR"; exit 143' TERM

    # --- packages ------------------------------------------------------------
    # This MUST come before anything that uses wget: a fresh Termux does
    # not have it yet (v1.0.0 checked the connection with a wget that was
    # not installed, and always died on 'wget: command not found'). The
    # package manager itself is the real connectivity test here.
    # 'pkg' ships with every Termux installation (termux-tools), so it is
    # the one and only package manager this script talks to.
    step 2 "Installing proot, tar and wget (pkg)"
    have pkg || die "The 'pkg' command was not found.
This script only works inside a real Termux app."

    start_spinner "Refreshing the package list ..."
    if ! pkg update -y >"$WORK_DIR/pkg.log" 2>&1; then
        stop_spinner
        warn "'pkg update' failed (is the internet up?). Trying to continue anyway."
    else
        stop_spinner
    fi
    start_spinner "Installing proot, tar and wget (this can take a minute) ..."
    if ! pkg install -y proot tar wget >>"$WORK_DIR/pkg.log" 2>&1; then
        stop_spinner
        warn "Package installation failed. Last log lines:"
        tail -n 15 "$WORK_DIR/pkg.log" >&2
        die "That is usually the internet connection or a repository problem.
Fix what the log above complains about, then re-run:  ./proot.sh setup"
    fi
    stop_spinner
    local c
    for c in proot tar wget; do
        have "$c" || die "'$c' did not install correctly. Re-run:  ./proot.sh setup"
    done
    ok "proot, tar and wget are ready."

    # --- network pre-flight (wget exists by now; pkg already proved that
    #     Termux's own mirrors work, this checks Alpine's) -------------------
    step 3 "Checking the way to Alpine's servers"
    msg "Checking that we can reach Alpine's servers ..."
    local m reached=""
    for m in $ALPINE_MIRRORS; do
        if wget -q -T 15 --spider "$m/"; then reached=1; break; fi
    done
    if [ -z "$reached" ]; then
        die "Termux's mirrors work, but Alpine's servers are unreachable
from your network. Check your connection and run:  ./proot.sh setup"
    fi

    # --- download -----------------------------------------------------------
    step 4 "Downloading Alpine (checksum verified)"
    if ! fetch_release; then
        die "Could not get Alpine from any official mirror. Check your
internet connection, then re-run:  ./proot.sh setup"
    fi

    # --- extract & configure ------------------------------------------------
    step 5 "Unpacking and configuring"
    start_spinner "Unpacking Alpine $ALPINE_VER ($ALPINE_ARCH) ..."
    local rfs="$WORK_DIR/rootfs"
    if ! mkdir -p "$rfs"; then
        stop_spinner
        die "Could not prepare the install directory."
    fi

    # GNU tar warns about extended headers it does not know; busybox tar
    # does not understand that flag, hence the version check.
    local tar_opts=( -xzf "$WORK_DIR/$ALPINE_FILE" -C "$rfs" --exclude=./dev --exclude=dev )
    if tar --version 2>/dev/null | grep -qi 'GNU tar'; then
        tar_opts+=( --warning=no-unknown-keyword )
    fi
    if ! tar "${tar_opts[@]}"; then
        stop_spinner
        die "Extraction failed. Free up space and re-run:  ./proot.sh setup"
    fi
    stop_spinner
    ok "Unpacked."

    # Mount points proot will bind things onto at login time
    mkdir -p "$rfs/dev" "$rfs/dev/shm" "$rfs/proc" "$rfs/sys" \
             "$rfs/sdcard" "$rfs/mnt/sdcard"
    chmod 1777 "$rfs/tmp" 2>/dev/null || true

    # Guest-side DNS fallback (the host resolv.conf is bound on top at login)
    ensure_host_resolv
    printf '%s\n' "$DNS_FALLBACK" > "$rfs/etc/resolv.conf"

    # Install marker -- proof that setup ran to completion
    printf 'arch=%s\nversion=%s\ndate=%s\nscript=%s\n' \
        "$ALPINE_ARCH" "$ALPINE_VER" "$(date +%Y-%m-%d 2>/dev/null || echo unknown)" \
        "$VERSION" > "$rfs/etc/.proot-sh-installed"

    # --- sanity check -------------------------------------------------------
    [ -x "$rfs/bin/busybox" ] && [ -f "$rfs/etc/alpine-release" ] \
        || die "The extracted system looks broken. Re-run:  ./proot.sh setup"

    # --- swap into place (atomic-ish: partial installs are never visible) ---
    if ! mv "$rfs" "$ROOTFS_DIR"; then
        die "Could not move Alpine into place."
    fi

    step 6 "Finishing up"
    ok "Alpine $(rootfs_version) is ready (in $ROOTFS_DIR)."

    # Size report without awk: 'du -sk' prints "N<TAB>path", so everything
    # from the first tab onwards is just the path.
    local size_line size_kb
    size_line="$(du -sk "$ROOTFS_DIR" 2>/dev/null || true)"
    size_kb="${size_line%%[$'\t' ]*}"
    size_kb="${size_kb//[!0-9]/}"
    if [ -n "$size_kb" ]; then
        msg "Total disk usage: about $(( size_kb / 1024 )) MB. Small, as promised."
    fi

    # The receipt. Plain ASCII, 32 columns wide, green when the terminal
    # can show it.
    printf '%s' "${C_OK}"
    printf '  +------------------------------+\n'
    printf '  |  Installation complete!      |\n'
    printf '  |                              |\n'
    printf '  |  enter it : ./proot.sh shell |\n'
    printf '  |  location : ~/.proot-alpine  |\n'
    printf '  +------------------------------+\n'
    printf '%s\n' "${C_RESET}"

    # When a human is watching (and nobody is piping us around), offer to
    # walk straight in. Scripts and pipes never see this question.
    if [ -t 0 ] && [ -t 1 ] && [ "${SETUP_INVITE:-yes}" != "no" ]; then
        local go_in=""
        ask "Step inside Alpine right now? [y/N] "
        if read -r go_in \
           && { [ "$go_in" = "y" ] || [ "$go_in" = "Y" ] || [ "$go_in" = "yes" ]; }; then
            printf '\n'
            MENU_MODE=1
            enter_shell
            return 0
        fi
        printf '\n'
        msg "No problem -- './proot.sh shell' whenever you feel like it."
    fi
}

# ----------------------------------------------------------------------------
# shell -- enter Alpine as root
# ----------------------------------------------------------------------------

usage_shell() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh shell

${C_BOLD}WHAT IT DOES${C_RESET}
  Starts Alpine and drops you into a root
  shell, so 'apk add ...' works right away.

  Inside Alpine:
  /sdcard    your Android shared storage
  exit       back to Termux (or press Ctrl-D)

${C_BOLD}TROUBLESHOOTING${C_RESET}
  On very old devices, if the shell dies
  with a 'seccomp' error, run it like this:
  PROOT_NO_SECCOMP=1 ./proot.sh shell
EOF
}

cmd_shell() {
    check_termux
    if ! rootfs_is_valid; then
        if [ -e "$ROOTFS_DIR" ]; then
            die "The Alpine installation is incomplete (a setup may have been
interrupted). Fix it by re-running:  ./proot.sh setup"
        fi
        die "Alpine is not set up yet. Run this first:  ./proot.sh setup"
    fi
    # Called from the command line: replace this process with proot, so
    # Ctrl-C and exit codes behave exactly like a normal program's.
    MENU_MODE=0
    enter_shell
}

# Resolve proot the same way it will be found in PATH (pkg installs it
# into $PREFIX/bin, but resolving properly costs nothing and never lies).
guest_proot_bin() {
    local pb
    pb="$(command -v proot 2>/dev/null || true)"
    [ -n "$pb" ] || pb="$PREFIX/bin/proot"
    have proot || [ -x "$pb" ] \
        || die "'proot' is missing. Re-run:  ./proot.sh setup"
    printf '%s\n' "$pb"
}

# Fill the global PROOT_ARGS array with the flags every guest session
# needs. Two modes:
#   kill : add --kill-on-exit (logins and one-shots -- nothing is left
#          running behind them)
#   keep : leave it out (the desktop session has to outlive this script,
#          so it is started detached instead)
build_proot_args() {
    local mode="${1:-kill}"
    ensure_host_resolv
    PROOT_ARGS=()
    if [ "$mode" = "kill" ]; then
        PROOT_ARGS+=( --kill-on-exit )
    fi
    # --link2symlink : keeps installs happy on filesystems without hardlinks
    # --sysvipc      : System V IPC works (databases, browsers, ...)
    # -L             : correct lstat sizes on symlinks (quieter apk/dpkg)
    # -0             : pretend to be root, so apk / setup scripts behave
    PROOT_ARGS+=(
        --link2symlink
        --sysvipc
        -L
        -0
        --rootfs="$ROOTFS_DIR"
        --cwd=/root
        --bind=/dev
        --bind=/proc
        --bind=/sys
        --bind=/dev/urandom:/dev/random
        --bind="$PREFIX/etc/resolv.conf:/etc/resolv.conf"
    )

    # Small conveniences that make the guest feel like a real machine.
    # Only added when the host lacks the usual /dev symlinks.
    if [ ! -e /dev/fd ] && [ ! -L /dev/fd ]; then
        PROOT_ARGS+=( --bind=/proc/self/fd:/dev/fd )
    fi
    [ -e /dev/stdin ]  || PROOT_ARGS+=( --bind=/proc/self/fd/0:/dev/stdin )
    [ -e /dev/stdout ] || PROOT_ARGS+=( --bind=/proc/self/fd/1:/dev/stdout )
    [ -e /dev/stderr ] || PROOT_ARGS+=( --bind=/proc/self/fd/2:/dev/stderr )

    # POSIX shared memory. Some software (databases, browsers) refuses
    # to start without a working /dev/shm, so the guest gets one backed
    # by a folder inside the rootfs itself.
    if mkdir -p "$ROOTFS_DIR/dev/shm" 2>/dev/null; then
        PROOT_ARGS+=( --bind="$ROOTFS_DIR/dev/shm:/dev/shm" )
    fi

    # Android shared storage, mirroring what proot-distro does
    local found_storage=0 sp
    if [ -d /storage ] && [ -r /storage ]; then
        PROOT_ARGS+=( --bind=/storage )
        if [ -r /storage/emulated/0 ]; then
            PROOT_ARGS+=( --bind=/storage/emulated/0:/sdcard )
            PROOT_ARGS+=( --bind=/storage/emulated/0:/mnt/sdcard )
            found_storage=1
        fi
    else
        for sp in /storage/self/primary /storage/emulated/0 /sdcard; do
            if [ -r "$sp" ]; then
                PROOT_ARGS+=( --bind="$sp:/sdcard" \
                              --bind="$sp:/mnt/sdcard" \
                              --bind="$sp:/storage/emulated/0" \
                              --bind="$sp:/storage/self/primary" )
                found_storage=1
                break
            fi
        done
    fi
    if [ "$found_storage" -eq 0 ]; then
        warn "Shared storage is not accessible (try 'termux-setup-storage')."
    fi

    # Android system directories. Reading build.prop or poking at the
    # device from inside Alpine is a thing people do, and proot-distro
    # binds these by default too. Each one is skipped silently when the
    # host does not expose it (older Androids lack /apex and friends).
    local sysp
    for sysp in /apex /odm /product /system /system_ext /vendor \
                /linkerconfig/ld.config.txt \
                /linkerconfig/com.android.art/ld.config.txt \
                /plat_property_contexts /property_contexts; do
        if { [ -d "$sysp" ] && [ -x "$sysp" ]; } \
           || { [ -f "$sysp" ] && [ -r "$sysp" ]; }; then
            PROOT_ARGS+=( --bind="$sysp" )
        fi
    done
}

# The clean guest environment every session shares. proot-distro's
# hard-won rules, adopted here:
#   - the guest starts from a clean environment (env -i): Termux's
#     LD_PRELOAD (libtermux-exec.so) must never leak inside;
#   - LD_LIBRARY_PATH is deliberately NOT passed. proot finds its own
#     libraries through its built-in rpath (proot-distro has stripped
#     this variable for years), and a leaked path could let a tampered
#     rootfs feed its own .so files into the guest loader;
#   - PROOT_NO_SECCOMP is the official escape hatch for devices whose
#     kernel chokes on proot's seccomp filter, so it is forwarded.
build_guest_env() {
    GUEST_ENV=(
        HOME=/root USER=root
        TERM="${TERM:-xterm-256color}"
        LANG=C.UTF-8
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    )
    [ -n "${PROOT_NO_SECCOMP:-}" ] && GUEST_ENV+=("PROOT_NO_SECCOMP=${PROOT_NO_SECCOMP}")
}

# Run a one-shot command inside Alpine with the very same flags as a
# login session. Output passes straight through and the exit code is
# the guest command's own, so callers can react to failures.
guest_run() {
    local pb
    pb="$(guest_proot_bin)"
    build_proot_args kill
    build_guest_env
    env -i "${GUEST_ENV[@]}" "$pb" "${PROOT_ARGS[@]}" /bin/sh -lc "$*"
}

# The real login. Assumes the rootfs is healthy (cmd_shell and the menu
# both check that first). With MENU_MODE=1 it runs proot in the foreground
# and comes back afterwards, so the menu can pick up where it left off.
enter_shell() {
    local proot_bin
    proot_bin="$(guest_proot_bin)"
    build_proot_args kill
    build_guest_env

    msg "Entering Alpine $(rootfs_version). Type 'exit' to come back."
    if [ "${MENU_MODE:-0}" = "1" ]; then
        env -i "${GUEST_ENV[@]}" \
            "$proot_bin" "${PROOT_ARGS[@]}" /bin/sh -l
        printf '\n'
        ok "Left Alpine. You are back in Termux."
    else
        exec env -i "${GUEST_ENV[@]}" \
            "$proot_bin" "${PROOT_ARGS[@]}" /bin/sh -l
    fi
}

# ----------------------------------------------------------------------------
# remove -- clean slate
# ----------------------------------------------------------------------------

usage_remove() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh remove

${C_BOLD}WHAT IT DOES${C_RESET}
  Deletes the Alpine installation completely
  (about 10-15 MB). Your Termux packages and
  your personal files are not touched.

  You can always re-install later with:
  ./proot.sh setup
EOF
}

cmd_remove() {
    check_termux
    if [ ! -d "$ROOTFS_DIR" ]; then
        msg "Nothing to remove -- Alpine is not installed."
        exit 0
    fi
    ask "Delete Alpine and ALL data inside $ROOTFS_DIR? [y/N] "
    read -r ans || ans=""
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ] || [ "$ans" = "yes" ] || [ "$ans" = "YES" ]; then
        if [ -z "$ROOTFS_DIR" ] || [ "$ROOTFS_DIR" = "/" ]; then
            die "Refusing to delete an unsafe path."
        fi
        start_spinner "Removing $ROOTFS_DIR ..."
        rm -rf "$ROOTFS_DIR"
        stop_spinner
        ok "Done. Alpine is gone. ('./proot.sh setup' brings it back anytime.)"
    else
        msg "Cancelled. Nothing was deleted."
    fi
}

# ----------------------------------------------------------------------------
# info -- a small report about the workspace
# ----------------------------------------------------------------------------

usage_info() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh info

${C_BOLD}WHAT IT DOES${C_RESET}
  Prints a small report about your Alpine
  workspace: version, architecture, size on
  disk and location -- plus the two commands
  to enter or remove it. A quick way to check
  that the installation is healthy.
EOF
}

cmd_info() {
    check_termux
    if ! rootfs_is_valid; then
        msg "Alpine is not installed yet."
        msg "Set it up with:  ${C_BOLD}./proot.sh setup${C_RESET}"
        return 0
    fi

    # Read the install marker (key=value lines), pure shell.
    local key val arch="" ver=""
    while IFS='=' read -r key val; do
        if [ "$key" = "arch" ]; then arch="$val"; fi
        if [ "$key" = "version" ]; then ver="$val"; fi
    done < "$ROOTFS_DIR/etc/.proot-sh-installed"
    if [ -z "$ver" ]; then
        ver="$(rootfs_version)"
    fi

    printf '\n%s  Alpine workspace%s\n' "${C_BOLD}" "${C_RESET}"
    printf '  --------------------------------\n'
    printf '  installed : Alpine %s (%s)\n' "$ver" "$arch"
    printf '  location  : %s\n' "$ROOTFS_DIR"
    local size_line size_kb
    size_line="$(du -sk "$ROOTFS_DIR" 2>/dev/null || true)"
    size_kb="${size_line%%[$'\t' ]*}"
    size_kb="${size_kb//[!0-9]/}"
    if [ -n "$size_kb" ]; then
        printf '  disk used : about %s MB\n' "$(( size_kb / 1024 ))"
    fi
    printf '  enter     : ./proot.sh shell\n'
    printf '  remove    : ./proot.sh remove\n'
    if desktop_is_installed; then
        if desktop_is_running; then
            printf '  desktop   : running (VNC 127.0.0.1:%s)\n' "$VNC_PORT"
        else
            printf '  desktop   : installed, not running\n'
        fi
    else
        printf '  desktop   : not installed\n'
    fi
    printf '\n'
    msg "Inside Alpine, your Android storage lives at /sdcard."
    msg "Install apps with:  apk add <name>   (for example: apk add nano)"
}

# ----------------------------------------------------------------------------
# desktop -- LXQt + a VNC server, running inside Alpine (optional add-on)
#
# The desktop is installed INSIDE Alpine with apk (Alpine's own repos).
# A generated script pair starts/stops Xvnc + LXQt, and the session is
# kept alive by a detached proot process, so the graphical apps survive
# after this script itself has exited.
# ----------------------------------------------------------------------------

usage_desktop_setup() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh desktop-setup

${C_BOLD}WHAT IT DOES${C_RESET}
  Turns Alpine into a graphical workstation:

  1. installs the LXQt desktop, the TigerVNC
     server and fonts INSIDE Alpine (via apk,
     a few hundred MB -- be patient)
  2. writes a ready-made VNC session file
  3. asks for a VNC password (scripts can
     pass PROOT_VNC_PASS=<pw> instead)

  Needs about 1-2 GB of free space.
  Safe to re-run: done means done.

${C_BOLD}NEXT${C_RESET}
  ./proot.sh desktop-start
EOF
}

usage_desktop_start() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh desktop-start

${C_BOLD}WHAT IT DOES${C_RESET}
  Starts the LXQt desktop in the background
  and keeps it running even after this
  script exits (a wake lock keeps Android
  from reaping it).

  Connect from any VNC app on this phone:
    address  : 127.0.0.1:5901
    password : the one you picked during
               desktop-setup

${C_BOLD}TROUBLESHOOTING${C_RESET}
  Blank or slow desktop? Look at:
  ~/.proot-alpine/root/.vnc/session.log
  and re-run this command.
EOF
}

usage_desktop_stop() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh desktop-stop

${C_BOLD}WHAT IT DOES${C_RESET}
  Ends the VNC session and closes the LXQt
  desktop. Alpine and your files stay
  untouched -- only the graphical session
  goes away. Safe to run when nothing is
  running.
EOF
}

# The guest-side scripts. Written once by desktop-setup into the rootfs,
# plain POSIX sh so busybox ash is happy. ($ is escaped where the guest
# needs the literal sign at run time; unescaped ones are baked in here.)
write_desktop_scripts() {
    mkdir -p "$VNC_DIR" || die "Could not create $VNC_DIR"
    cat > "$VNC_DIR/start-desktop.sh" <<START
#!/bin/sh
# start-desktop.sh -- generated by proot.sh $VERSION, runs INSIDE Alpine.
# Brings up the Xvnc server and the LXQt session on display :$VNC_DISPLAY.
V=/root/.vnc
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true
echo \$\$ > \$V/session.pid
if [ -f \$V/xvnc.pid ] && kill -0 "\$(cat \$V/xvnc.pid)" 2>/dev/null; then
    echo "Xvnc is already running on :$VNC_DISPLAY."
    exit 0
fi
Xvnc :$VNC_DISPLAY -geometry $VNC_GEOM -depth 24 \\
    -rfbauth /root/.vnc/passwd -rfbport $VNC_PORT \\
    -localhost yes -NeverShared &
echo \$! > \$V/xvnc.pid
n=0
while [ \$n -lt 20 ]; do
    [ -S /tmp/.X11-unix/X$VNC_DISPLAY ] && break
    sleep 1
    n=\$((n+1))
done
DISPLAY=:$VNC_DISPLAY dbus-run-session -- startlxqt &
echo \$! > \$V/lxqt.pid
echo "Desktop is up. Connect a VNC client to 127.0.0.1:$VNC_PORT."
wait
START
    cat > "$VNC_DIR/stop-desktop.sh" <<STOP
#!/bin/sh
# stop-desktop.sh -- generated by proot.sh $VERSION, runs INSIDE Alpine.
V=/root/.vnc
n=0
for f in lxqt.pid xvnc.pid session.pid; do
    if [ -f \$V/\$f ]; then
        p="\$(cat \$V/\$f)"
        if [ -n "\$p" ] && kill -0 "\$p" 2>/dev/null; then
            kill "\$p" 2>/dev/null
            n=1
        fi
        rm -f \$V/\$f
    fi
done
pkill -f startlxqt 2>/dev/null || true
if [ "\$n" = "1" ]; then
    echo "Desktop stopped."
else
    echo "Desktop was not running."
fi
STOP
}

ask_vnc_password() {
    # Leaves the chosen password in the global VNC_PASS.
    if [ -n "${PROOT_VNC_PASS:-}" ]; then
        VNC_PASS="$PROOT_VNC_PASS"
        msg "Using the VNC password from PROOT_VNC_PASS."
        return 0
    fi
    if [ ! -t 0 ]; then
        # Nobody can answer a prompt (script or pipe): make one up. VNC
        # passwords only ever use the first 8 characters anyway.
        VNC_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 8)"
        if [ -z "$VNC_PASS" ]; then
            die "Could not generate a VNC password. Set PROOT_VNC_PASS=<pw>
and re-run:  ./proot.sh desktop-setup"
        fi
        warn "Auto-generated VNC password: ${VNC_PASS} (write it down!)"
        return 0
    fi
    local p1="" p2="" tries=0
    while [ $tries -lt 3 ]; do
        ask "Choose a VNC password (max 8 chars): "
        read -rs p1 || p1=""
        printf '\n'
        ask "Repeat it: "
        read -rs p2 || p2=""
        printf '\n'
        if [ -z "$p1" ]; then
            warn "The password cannot be empty."
        elif [ "$p1" != "$p2" ]; then
            warn "The two passwords did not match, try again."
        else
            if [ ${#p1} -gt 8 ]; then
                warn "VNC only uses the first 8 characters of a password."
            fi
            VNC_PASS="$p1"
            return 0
        fi
        tries=$((tries + 1))
    done
    die "Giving up after three tries. Re-run:  ./proot.sh desktop-setup"
}

cmd_desktop_setup() {
    check_termux
    if ! rootfs_is_valid; then
        die "Alpine is not installed yet. Run './proot.sh setup' first
(menu option 1 in the menu)."
    fi
    if desktop_is_installed; then
        ok "The desktop is already installed."
        msg "Start it with:  ${C_BOLD}./proot.sh desktop-start${C_RESET}"
        return 0
    fi

    printf '\n%s  Alpine desktop installer (LXQt + VNC)%s\n' \
        "${C_BOLD}" "${C_RESET}"
    printf '%s\n' "  -----------------------------------------------"

    dstep "1/4" "Checking the room for a desktop"
    check_disk_space 1200

    dstep "2/4" "Refreshing Alpine's package index"
    if ! guest_run "apk update"; then
        die "'apk update' failed inside Alpine. Enter the shell with
'./proot.sh shell' and run 'apk update' by hand to see why."
    fi

    dstep "3/4" "Installing LXQt + TigerVNC (hundreds of MB)"
    msg "This downloads a lot -- go make some tea."
    if ! guest_run "apk add $DESKTOP_PKGS"; then
        die "'apk add' failed inside Alpine. Check the messages above,
then re-run:  ./proot.sh desktop-setup"
    fi

    dstep "4/4" "Writing the session files + VNC password"
    write_desktop_scripts
    ask_vnc_password
    if ! printf '%s\n' "$VNC_PASS" \
            | guest_run "mkdir -p /root/.vnc && vncpasswd -f > /root/.vnc/passwd && chmod 600 /root/.vnc/passwd"; then
        die "'vncpasswd' failed inside Alpine. Re-run:  ./proot.sh desktop-setup"
    fi

    # Desktop marker: proof that the desktop add-on ran to completion.
    local key val m_arch=""
    while IFS='=' read -r key val; do
        if [ "$key" = "arch" ]; then m_arch="$val"; fi
    done < "$ROOTFS_DIR/etc/.proot-sh-installed"
    printf 'arch=%s\ndesktop=lxqt\ndisplay=:%s\nport=%s\ngeom=%s\ndate=%s\nscript=%s\n' \
        "$m_arch" "$VNC_DISPLAY" "$VNC_PORT" "$VNC_GEOM" \
        "$(date +%Y-%m-%d 2>/dev/null || echo unknown)" "$VERSION" \
        > "$DESKTOP_MARKER"

    # The receipt. Same style as the setup one, 34 columns wide.
    printf '%s' "${C_OK}"
    printf '  +--------------------------------+\n'
    printf '  |  Desktop installed!            |\n'
    printf '  |                                |\n'
    printf '  |  start it : ./proot.sh         |\n'
    printf '  |             desktop-start      |\n'
    printf '  |  connect  : 127.0.0.1:%s     |\n' "$VNC_PORT"
    printf '  |  client   : any VNC app        |\n'
    printf '  |             (AVNC, bVNC, ...)  |\n'
    printf '  +--------------------------------+\n'
    printf '%s\n' "${C_RESET}"
}

cmd_desktop_start() {
    check_termux
    if ! rootfs_is_valid; then
        die "Alpine is not installed yet. Run './proot.sh setup' first."
    fi
    if ! desktop_is_installed; then
        die "The desktop is not installed yet. Run
'./proot.sh desktop-setup' first (menu option 3)."
    fi
    if desktop_is_running; then
        ok "The desktop is already running (display :$VNC_DISPLAY)."
        msg "Connect any VNC client to 127.0.0.1:$VNC_PORT"
        return 0
    fi

    local pb bg i up=0
    pb="$(guest_proot_bin)"
    # "keep" mode: no --kill-on-exit, the desktop must outlive us. Guest
    # pids are real Termux pids (proot has no PID namespace), so the
    # stop command can reach them directly later.
    build_proot_args keep
    build_guest_env

    # Ask Android to leave the session alone while the screen is off.
    if have termux-wake-lock; then
        termux-wake-lock 2>/dev/null || true
        : > "$VNC_DIR/wakelock"
    fi

    : > "$VNC_DIR/session.log"
    msg "Starting the desktop in the background ..."
    if have nohup; then
        nohup env -i "${GUEST_ENV[@]}" "$pb" "${PROOT_ARGS[@]}" \
            /bin/sh /root/.vnc/start-desktop.sh \
            </dev/null >>"$VNC_DIR/session.log" 2>&1 &
    else
        env -i "${GUEST_ENV[@]}" "$pb" "${PROOT_ARGS[@]}" \
            /bin/sh /root/.vnc/start-desktop.sh \
            </dev/null >>"$VNC_DIR/session.log" 2>&1 &
    fi
    bg=$!

    # Give Xvnc a few seconds to open its socket; bail out early when
    # the background proot already died (config error, missing binary).
    i=0
    while [ $i -lt 8 ]; do
        if ! kill -0 "$bg" 2>/dev/null; then break; fi
        if [ -S "$ROOTFS_DIR/tmp/.X11-unix/X$VNC_DISPLAY" ]; then up=1; break; fi
        sleep 1
        i=$((i + 1))
    done
    if [ "$up" = "1" ]; then
        ok "Desktop is up (took ${i}s)."
    else
        warn "Still starting, or it failed -- details:"
        warn "$VNC_DIR/session.log"
    fi
    printf '  VNC address : 127.0.0.1:%s\n' "$VNC_PORT"
    printf '  VNC display : :%s (%s)\n' "$VNC_DISPLAY" "$VNC_GEOM"
    msg "Open any VNC app on this phone and connect to 127.0.0.1:$VNC_PORT"
}

cmd_desktop_stop() {
    check_termux
    if [ ! -d "$ROOTFS_DIR" ]; then
        msg "Nothing to stop -- Alpine is not installed."
        return 0
    fi
    if ! desktop_is_installed; then
        msg "The desktop is not installed -- nothing to stop."
        return 0
    fi
    msg "Stopping the desktop ..."
    # The one-shot below uses --kill-on-exit, which only reaps what THIS
    # proot call spawned -- the running desktop session is a different
    # proot process and is killed by the guest script instead.
    if ! guest_run "sh /root/.vnc/stop-desktop.sh"; then
        warn "The stop command had trouble -- check:"
        warn "$VNC_DIR/session.log"
    fi
    if [ -f "$VNC_DIR/wakelock" ]; then
        if have termux-wake-unlock; then
            termux-wake-unlock 2>/dev/null || true
        fi
        rm -f "$VNC_DIR/wakelock"
    fi
    ok "Done. ('./proot.sh desktop-start' brings it back anytime.)"
}

# ----------------------------------------------------------------------------
# menu -- the interactive TUI-ish front page
# ----------------------------------------------------------------------------

usage_menu() {
    cat <<EOF
${C_BOLD}USAGE${C_RESET}
  ./proot.sh            (no arguments)
  ./proot.sh menu

${C_BOLD}WHAT IT DOES${C_RESET}
  Opens a small interactive menu: pick a
  number, press Enter, done. The easiest way
  to use proot.sh on a phone. It only shows
  up in a real terminal -- in scripts and
  pipes you get the plain help instead.
  (PROOT_MENU_FORCE=1 forces it on, which
  is handy for scripts and tests.)
EOF
}

pause_menu() {
    printf '%s' "  Press Enter to go back to the menu..."
    local unused=""
    read -r unused || true
    printf '\n'
}

cmd_menu() {
    # A menu needs a keyboard and a screen. Piped around? Then plain help.
    # (PROOT_MENU_FORCE=1 forces the menu on -- handy for scripts/tests.)
    if [ -z "${PROOT_MENU_FORCE:-}" ] && { [ ! -t 0 ] || [ ! -t 1 ]; }; then
        usage_main
        return 0
    fi
    local choice="" go_in="" wanna=""
    while :; do
        printf '\033[H\033[2J'
        banner
        # One glance = one line about what is installed and running.
        if rootfs_is_valid; then
            printf '  Alpine : %s\n' "$(rootfs_version)"
            if desktop_is_installed; then
                if desktop_is_running; then
                    printf '  Desktop: running (VNC 127.0.0.1:%s)\n' "$VNC_PORT"
                else
                    printf '  Desktop: installed, not running\n'
                fi
            else
                printf '  Desktop: not installed yet\n'
            fi
        else
            printf '  Alpine : not installed yet\n'
        fi
        printf '\n'
        printf '   1) Install Alpine (setup)\n'
        printf '   2) Enter Alpine (shell)\n'
        printf '   3) Install desktop (LXQt + VNC)\n'
        printf '   4) Start desktop (VNC :1)\n'
        printf '   5) Stop desktop\n'
        printf '   6) Workspace info\n'
        printf '   7) Remove Alpine\n'
        printf '   8) Help\n'
        printf '   0) Exit\n\n'
        ask "Pick a number and press Enter: "
        if ! read -r choice; then
            printf '\n'
            return 0
        fi

        if [ "$choice" = "1" ]; then
            if ( SETUP_INVITE=no; cmd_setup ); then
                if rootfs_is_valid; then
                    ask "Step inside Alpine now? [Y/n] "
                    read -r go_in || go_in=""
                    if [ "$go_in" != "n" ] && [ "$go_in" != "N" ]; then
                        printf '\n'
                        MENU_MODE=1
                        enter_shell
                    fi
                fi
            fi
            pause_menu
        elif [ "$choice" = "2" ]; then
            if rootfs_is_valid; then
                MENU_MODE=1
                enter_shell
            else
                warn "Alpine is not installed yet."
                ask "Run the setup now? [y/N] "
                read -r wanna || wanna=""
                if [ "$wanna" = "y" ] || [ "$wanna" = "Y" ] || [ "$wanna" = "yes" ]; then
                    if ( SETUP_INVITE=no; cmd_setup ); then
                        if rootfs_is_valid; then
                            ask "Step inside Alpine now? [Y/n] "
                            read -r wanna || wanna=""
                            if [ "$wanna" != "n" ] && [ "$wanna" != "N" ]; then
                                printf '\n'
                                MENU_MODE=1
                                enter_shell
                            fi
                        fi
                    fi
                fi
            fi
            pause_menu
        elif [ "$choice" = "3" ]; then
            ( cmd_desktop_setup )
            pause_menu
        elif [ "$choice" = "4" ]; then
            ( cmd_desktop_start )
            pause_menu
        elif [ "$choice" = "5" ]; then
            ( cmd_desktop_stop )
            pause_menu
        elif [ "$choice" = "6" ]; then
            cmd_info
            pause_menu
        elif [ "$choice" = "7" ]; then
            ( cmd_remove )
            pause_menu
        elif [ "$choice" = "8" ]; then
            usage_main
            pause_menu
        elif [ "$choice" = "0" ]; then
            printf '  Bye!\n'
            return 0
        else
            warn "Not a valid option: '$choice' (pick 0-8)."
            pause_menu
        fi
    done
}

# ----------------------------------------------------------------------------
# Help & version
# ----------------------------------------------------------------------------

usage_main() {
    banner
    cat <<EOF
${C_BOLD}WHAT IS THIS?${C_RESET}
  One small file that puts a complete Alpine
  Linux inside Termux. No root needed, no
  bloat -- about 15 MB when installed. Want
  more? Add a full LXQt desktop with VNC.

${C_BOLD}COMMANDS${C_RESET}
  setup          one-time install of Alpine
  shell          enter Alpine as root (apk works)
  desktop-setup  add LXQt + VNC inside Alpine
  desktop-start  start the desktop (VNC :1)
  desktop-stop   stop the desktop session
  info           show what is installed and its size
  remove         delete the Alpine installation
  menu           interactive menu (same as no args)

${C_BOLD}HELP${C_RESET}
  ./proot.sh --help                 this page
  ./proot.sh setup --help           about setup
  ./proot.sh shell --help           about shell
  ./proot.sh desktop-setup --help   about desktop
  ./proot.sh info --help            about info
  ./proot.sh remove --help          about remove
  ./proot.sh --version              version info

${C_BOLD}QUICK START (the menu way)${C_RESET}
  ./proot.sh          opens the menu. Then:
  pick 1   install Alpine (one time)
  pick 2   enter Alpine, then: apk add nano
  pick 3   add a LXQt desktop (optional)
  pick 4   start it, connect VNC to
           127.0.0.1:5901 with any VNC app
  pick 0   leave

${C_BOLD}GOOD TO KNOW${C_RESET}
  Alpine lives in:  ~/.proot-alpine
  /sdcard is your Android shared storage
  Downloads come only from official sources
  (Termux repo + Alpine's own CDN and apk
  repos) and are checksum-verified before use.
EOF
}

show_version() {
    printf 'proot.sh %s\n' "$VERSION"
}

unknown_subcommand() {
    printf '%s\n' "${C_BAD}[ XX ]${C_RESET} Unknown command: '$1'" >&2
    printf '%s\n' "Run '${C_BOLD}./proot.sh --help${C_RESET}' to see what this script can do." >&2
    exit 1
}

# Per-command argument handling: every subcommand understands -h/--help,
# anything else is rejected loudly instead of silently ignored.
handle_common_args() {
    local usage_fn="$1" cmd="$2"
    shift 2
    while [ $# -gt 0 ]; do
        if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
            "$usage_fn"
            exit 0
        else
            printf '%s\n' "${C_BAD}[ XX ]${C_RESET} Unknown option for '$cmd': '$1'" >&2
            printf '%s\n' "Try '${C_BOLD}./proot.sh $cmd --help${C_RESET}'." >&2
            exit 1
        fi
    done
}

main() {
    local cmd="${1:-}"
    if [ -z "$cmd" ]; then
        # No arguments: open the menu (it falls back to the help text when
        # stdin/stdout is not a real terminal).
        cmd_menu
    elif [ "$cmd" = "menu" ]; then
        shift
        handle_common_args usage_menu menu "$@"
        cmd_menu
    elif [ "$cmd" = "setup" ] || [ "$cmd" = "set-up" ]; then
        shift
        handle_common_args usage_setup setup "$@"
        cmd_setup
    elif [ "$cmd" = "shell" ]; then
        shift
        handle_common_args usage_shell shell "$@"
        cmd_shell
    elif [ "$cmd" = "desktop-setup" ]; then
        shift
        handle_common_args usage_desktop_setup desktop-setup "$@"
        cmd_desktop_setup
    elif [ "$cmd" = "desktop-start" ]; then
        shift
        handle_common_args usage_desktop_start desktop-start "$@"
        cmd_desktop_start
    elif [ "$cmd" = "desktop-stop" ]; then
        shift
        handle_common_args usage_desktop_stop desktop-stop "$@"
        cmd_desktop_stop
    elif [ "$cmd" = "info" ]; then
        shift
        handle_common_args usage_info info "$@"
        cmd_info
    elif [ "$cmd" = "remove" ]; then
        shift
        handle_common_args usage_remove remove "$@"
        cmd_remove
    elif [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ] || [ "$cmd" = "help" ]; then
        usage_main
    elif [ "$cmd" = "-V" ] || [ "$cmd" = "--version" ] || [ "$cmd" = "version" ]; then
        show_version
    else
        unknown_subcommand "$cmd"
    fi
}

# Only run main when executed directly (so the script can be sourced for tests)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
