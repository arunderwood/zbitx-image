# On a tty1 login (autologin or manual), launch X immediately so the
# sBitx.desktop autostart entry can fire. Other ttys / SSH sessions
# fall through to a normal shell.
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx -- -nocursor
fi

# Standard bash_profile bits if we didn't exec out above.
[ -r ~/.bashrc ] && . ~/.bashrc
