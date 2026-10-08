#!/bin/sh
echo testdata > /tmp/xzt.txt
rm -f /tmp/xzt.txt.xz
xz -k /tmp/xzt.txt && ls -la /tmp/xzt.txt.xz
tar tzf /tmp/xzt.txt.xz && echo AUTO-OK
