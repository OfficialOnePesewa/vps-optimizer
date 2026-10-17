# OP VPS Optimizer
BBR + low-latency tuning, keep-alive pinger and public BadVPN UDPGW for streaming, VoIP and gaming.
By **OP Data Solutions** (@OfficialOnePesewa)

## Install
```bash
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main/install.sh | sudo bash
```
Flags: `| sudo bash -s -- --no-badvpn` · `--no-tune` · `--ports "7100 7200 7300"`

## Folder structure
```
vps-optimizer/
├── install.sh
├── uninstall.sh
├── README.md
├── bin/
│   ├── op-optimizer        # tuning menu/CLI
│   ├── op-badvpn           # BadVPN manager
│   └── op-keepalive        # 2-minute ping keep-alive
├── config/
│   ├── sysctl-lowlatency.conf
│   ├── badvpn.env
│   └── keepalive.env
└── systemd/
    ├── badvpn@.service
    ├── op-optimizer-net.service
    ├── op-keepalive.service
    └── op-keepalive.timer
```

## Commands
```
op-optimizer [apply|status|restore|menu]
op-badvpn [install [ports]|status|restart|open|close|remove]
BADVPN_FORCE=1 op-badvpn install     # rebuild from source
```
Edit `/etc/op-optimizer/badvpn.env` then `op-badvpn restart` to change bind/ports/limits.

## Security
BadVPN is bound publicly (0.0.0.0) on 7100/7200/7300. That makes it an open UDP relay;
limit it to your users' IPs with your firewall if you can.
