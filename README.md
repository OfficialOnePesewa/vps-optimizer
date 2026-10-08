# OP VPS Optimizer
BBR + low-latency tuning and public BadVPN UDPGW for VoIP, gaming and streaming.
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
│   ├── op-optimizer          # tuning menu/CLI
│   └── op-badvpn             # BadVPN manager
├── config/
│   ├── sysctl-lowlatency.conf  # BBR + low-latency template
│   └── badvpn.env              # BIND=0.0.0.0, ports, limits
└── systemd/
    ├── badvpn@.service         # one instance per port
    └── op-optimizer-net.service # boot-time qdisc/NIC tuning
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
