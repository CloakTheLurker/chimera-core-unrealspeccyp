#!/bin/sh
# Stop the detached miniBox test run (same build dir the guest link needs).
pkill -f "meson.py test" || true
pkill -f "ninja" || true
pkill -f "make -j install" || true
sleep 2
pgrep -af "meson|ninja|make -j" || echo "build quiet"
