#!/usr/bin/env python3
"""Tiny TUI that enables SGR mouse tracking and prints click events."""
import sys
import tty
import termios
import signal

old_settings = termios.tcgetattr(sys.stdin)


def cleanup(*_):
    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
    sys.stdout.write("\x1b[?1006l\x1b[?1000l")
    sys.stdout.flush()
    sys.exit(0)


signal.signal(signal.SIGINT, cleanup)

# Set raw mode so we get characters immediately
tty.setraw(sys.stdin)

# Enable mouse tracking (normal mode 1000 + SGR mode 1006)
sys.stdout.write("\x1b[?1000h\x1b[?1006h")
sys.stdout.write("MOUSE_READY\r\n")
sys.stdout.flush()

try:
    while True:
        ch = sys.stdin.read(1)
        if ch == "\x1b":
            seq = ch
            while True:
                c = sys.stdin.read(1)
                seq += c
                if c in ("M", "m"):
                    break
            # Parse SGR: \x1b[<btn;col;rowM or m
            inner = seq[3:-1]  # strip \x1b[< and M/m
            parts = inner.split(";")
            action = "PRESS" if seq[-1] == "M" else "RELEASE"
            sys.stdout.write(
                f"MOUSE_{action}_btn{parts[0]}_col{parts[1]}_row{parts[2]}\r\n"
            )
            sys.stdout.flush()
        elif ch == "q":
            break
finally:
    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
    sys.stdout.write("\x1b[?1006l\x1b[?1000l")
    sys.stdout.flush()
