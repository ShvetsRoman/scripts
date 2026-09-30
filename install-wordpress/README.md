# WordPress Stack Installer V2.0

## Internet

```bash
sudo ./wordpress-stack.sh \
  --mode internet \
  --domain example.com \
  --email admin@example.com
```

## LAN

```bash
sudo ./wordpress-stack.sh --mode lan
```

## Optional host firewall integration

```bash
sudo ./wordpress-stack.sh \
  --mode internet \
  --domain example.com \
  --email admin@example.com \
  --manage-firewall
```

The generated runtime stack is placed in `/opt/wordpress` by default.
