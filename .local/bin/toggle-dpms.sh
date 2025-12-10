#!/bin/bash

# Cek apakah DPMS (Hemat Daya) sedang aktif?
if xset q | grep -q "DPMS is Enabled"; then
    # Jika Aktif -> Matikan (Masuk Mode Presentasi/Nonton)
    xset s off -dpms
    notify-send -u low -t 2000 "☕ Coffee Mode: ON" "Auto-lock & Screen OFF disabled."
else
    # Jika Mati -> Nyalakan Kembali (Kembali ke Default)
    # Mengembalikan ke settingan yang ada di config i3 (xset s 600 dpms 600...)
    xset s on +dpms
    notify-send -u low -t 2000 "☕ Coffee Mode: OFF" "Auto-lock & Screen OFF enabled."
fi