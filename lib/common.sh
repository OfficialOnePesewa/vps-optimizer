#!/usr/bin/env bash
# VPS Optimizer - shared library
# shellcheck shell=bash

bytes_human() {
    local b="${1:-0}"
    if   (( b < 1024 ));          then echo "${b} B"
    elif (( b < 1048576 ));       then awk -v b="$b" 'BEGIN { printf "%.2f KiB", b/1024 }'
    elif (( b < 1073741824 ));    then awk -v b="$b" 'BEGIN { printf "%.2f MiB", b/1048576 }'
    else                               awk -v b="$b" 'BEGIN { printf "%.2f GiB", b/1073741824 }'
    fi
}

primary_iface() {
    ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}'
}

mem_total_mb() {
    awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo
}
