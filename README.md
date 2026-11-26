# VPS Optimizer — Mobile LTE/H+ & Streaming Edition

Turns a stock Linux VPS into a high-throughput, ultra-stable server optimized for **ZIVPN (UDP)**, **H+/LTE mobile networks**, and **1080p/4K streaming**.

* **BBR + FQ:** Ignores mobile packet loss and prevents bufferbloat.
* **MTU Probing:** Fixes mobile network fragmentation (keeps YouTube from buffering).
* **CGNAT Keepalive:** Prevents mobile carriers from dropping idle UDP connections.
* **Mbps-Native Tooling:** All speed tests and live status outputs are strictly in Mbps/Gbps.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main/install.sh | sudo bash
