# TDZ Payload Proxy

A single-instance HTTP payload tunnel with TDZ branding and a compact `tdzp` manager.

## Behaviour

1. The proxy listens on one editable **public TCP port**.
2. It accepts an HTTP-style payload header.
3. It returns `HTTP/1.1 101 Switching Protocols`.
4. It relays the remaining raw TCP stream to `127.0.0.1:<backend-port>`.

This preserves the original proxy behaviour while adding a clean installer, status screen, safe port editing, rollback, managed firewall rules, and complete uninstall.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/yeasinulhoquetuhin/TDZ-TG-PAYLOAD-INJ/master/install.sh -o /tmp/tdzp-install.sh
sudo bash /tmp/tdzp-install.sh
```

For a local checkout:

```bash
sudo bash install.sh
```

The installer shows progress first, then asks for:

- Public listening port
- Local backend port, such as SSH `22` or a local V2Ray port

## Manager

```bash
tdzp
```

Menu options:

- Edit Public Port
- Edit Backend Port
- View Proxy Status
- Uninstall TDZ Payload Proxy

The aliases `TDZP` and `tdZp` are also installed, but lowercase `tdzp` is recommended.

## Files installed

- `/usr/local/bin/tdzp`
- `/usr/local/lib/tdz-payload/tdz_payload_proxy.py`
- `/etc/tdz-payload/tdzp.conf`
- `/etc/systemd/system/tdz-payload.service`
- `/etc/sysctl.d/99-tdz-payload.conf`

Uninstall removes the service, command aliases, runtime, configuration, managed firewall rule, dedicated service account, and TDZ network-tuning file.
