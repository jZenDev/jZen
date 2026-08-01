#!/usr/bin/env python3
"""Choose the Flutter device to run a native build on, and report its platform.

Nobody should have to copy a UUID out of `flutter devices` to run their own app, so:

  - ZEN_TARGET (an id or a name) wins when it is set;
  - one attached native device is used without asking;
  - several produce a numbered menu, read from /dev/tty so it works under `task`.

It prints one line to stdout, `<device-id>\t<platform>`, and everything a human reads to stderr,
so the caller can capture the answer without the conversation coming with it.

**The platform comes from Flutter, not from the shape of the id.** `flutter devices --machine`
reports `targetPlatform` per device; an id cannot be read for it, because `emulator-5554` and a
simulator UUID are both just strings. Guessing there is how an Android emulator once compiled with
ZEN_PLATFORM=ios and skipped the JDK check that would have explained the failure.
"""

import json
import os
import subprocess
import sys

# Flutter's targetPlatform prefixes mapped to what ZEN_PLATFORM calls them. Web is deliberately
# absent: `task run:demo` runs the web app, and this is the native counterpart.
FAMILIES = {"darwin": "macos", "ios": "ios", "android": "android"}


def die(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def family(device):
    target = device.get("targetPlatform") or ""
    for prefix, name in FAMILIES.items():
        if target.startswith(prefix):
            return name
    return None


def devices():
    try:
        result = subprocess.run(
            ["flutter", "devices", "--machine"], capture_output=True, text=True
        )
    except FileNotFoundError:
        die("`flutter` is not on PATH. Run `task doctor`.")
    try:
        return json.loads(result.stdout)
    except ValueError:
        die(
            "Could not read `flutter devices --machine`:\n"
            + (result.stderr.strip() or result.stdout.strip() or "(no output)")
        )


def choose(usable):
    wanted = os.environ.get("ZEN_TARGET", "").strip()
    if wanted:
        for device in usable:
            if wanted in (device["id"], device["name"]):
                return device
        die(
            "No native device matches ZEN_TARGET=%s.\nAttached: %s"
            % (wanted, ", ".join(d["id"] for d in usable) or "(none)")
        )

    if not usable:
        die(
            "No native device is attached.\n"
            "Boot an iOS Simulator or an Android emulator, or run on this Mac itself."
        )

    if len(usable) == 1:
        only = usable[0]
        print(
            "Using the only attached device: %s (%s)" % (only["name"], only["id"]),
            file=sys.stderr,
        )
        return only

    print("Several devices are attached:", file=sys.stderr)
    for index, device in enumerate(usable, 1):
        print(
            "  %d) %-28s %-8s %s" % (index, device["name"], family(device), device["id"]),
            file=sys.stderr,
        )

    # /dev/tty rather than stdin: this runs inside a command substitution, so stdin is not the
    # terminal. A non-interactive caller (CI) has no tty at all, and is told what to pass instead
    # of being left waiting at a prompt nobody can see.
    try:
        tty = open("/dev/tty")
    except OSError:
        die(
            "\nNothing to ask on (not an interactive shell). Name one:\n"
            "  ZEN_TARGET=<id> task run:demo:native"
        )

    print("Which one? [1-%d] " % len(usable), end="", file=sys.stderr, flush=True)
    answer = tty.readline().strip()
    if not answer.isdigit() or not 1 <= int(answer) <= len(usable):
        die("Not a choice on the list.")
    return usable[int(answer) - 1]


def main():
    usable = [d for d in devices() if family(d) and d.get("isSupported", True)]
    chosen = choose(usable)
    # ZEN_PLATFORM remains an override for an odd case, but it is no longer load-bearing.
    print("%s\t%s" % (chosen["id"], os.environ.get("ZEN_PLATFORM") or family(chosen)))


if __name__ == "__main__":
    main()
