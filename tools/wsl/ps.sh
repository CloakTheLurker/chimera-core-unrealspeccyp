#!/bin/sh
pgrep -af "guest-link|ninja|g\+\+|musl-gcc|meson" | head -n 10 || echo "nothing building"
