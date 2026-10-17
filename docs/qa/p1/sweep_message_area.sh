#!/usr/bin/env bash
# 扫整个会话，输出若干 dump
DEV=$1; PREFIX=$2; N=${3:-14}
export PATH="$PATH:/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains"
# 先滚到底
for i in 1 2 3 4 5 6 7 8; do hdc -t $DEV shell "uitest uiInput swipe 1400 700 1400 2100 200" >/dev/null 2>&1; done
sleep 1
for i in $(seq 1 $N); do
  hdc -t $DEV shell "uitest dumpLayout -p /data/local/tmp/$2.json" >/dev/null 2>&1
  hdc -t $DEV file recv /data/local/tmp/$2.json /tmp/dsprobe/$2$i.json >/dev/null 2>&1
  hdc -t $DEV shell "uitest uiInput swipe 1400 2100 1400 700 200" >/dev/null 2>&1
  sleep 0.6
done
