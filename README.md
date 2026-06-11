# Installation Manual

## Installation Requirements

- `bash`
- `git`
- `docker`
- `docker compose`
- On Linux/EC2, use at least `3 GB` RAM, or `2 GB` RAM plus at least `2 GB` swap before starting the full stack.
- The startup script now refuses to launch on undersized Linux hosts unless you set `SEKANT_SKIP_HOST_RESOURCE_CHECK=1`.
- On Apple Silicon, enable Docker Desktop's `Use Rosetta for x86/amd64 emulation` for any amd64-only Sekant images.
- `sekant_server.sh` auto-detects image architecture per service and only pins `linux/amd64` for images that do not publish a native arm64 variant.

## 0) Create the Installation Directory

```bash
mkdir sekant
cd sekant
```

## 1) Clone the Release Repository

Run this in the empty folder you created above. The `.` at the end clones the repository into the current directory.

```bash
git clone --branch v1.2.5 --depth 1 https://github.com/rishi-sekantsec/management-console .
```

## 2) Start the Installer

```bash
bash sekant_server.sh
```

## 3) Post-Installation Checklist

### System Settings

- Log in to the console using the admin credentials.
- Navigate to `Admin > System > Console Settings`.
- In the `Security Settings` tab, set the `CUSTOMER KEY` if one is available.
- In the `System Settings` tab, set the display timezone.
- In `System Settings`, ensure `Default Security Dashboard Automatic Refresh Interval` is set to `300`.

### Individual Extension Testing

- Navigate to `Admin > System > Console Settings`.
- Open the `Security Settings` tab.
- Copy the `Event Logging URL` and `Auth Token`.
- On the test device, install the Sekant browser extension from the browser web store.
- Open the extension options by clicking the extension icon and then the gear/settings option.
- Paste the `Event Logging URL` and `Auth Token`.
- Set the required options and save them.

## Appendix

### TLS / Certificate Options

Use one of these three patterns:

#### Option 1: Ports 80/443 are available

- Start the stack normally and enter the public hostname during setup.
- Leave `./certs/` empty.
- Caddy will try to obtain and renew the public certificate automatically for that hostname.
- This is the simplest option when ports `80/443` are reachable from the internet.

#### Option 2: You already have a certificate and private key

- Place the files in `./certs/` before starting, or restart after adding them later.
- Supported filename pairs:
  - `tls.crt` + `tls.key`
  - `cert.pem` + `key.pem`
  - `fullchain.pem` + `privkey.pem`
- Configure the installer with the same hostname covered by that certificate.
- This works even when Sekant is served on a custom HTTPS port such as `6780`; certificate validity is based on the hostname, not the port.

#### Option 3: You do not have the key, but you can edit DNS TXT records

- Run `bash certs/generate-public-cert.sh`.
- The helper uses Dockerized `acme.sh` in manual DNS mode, prompts for the hostname, prints the `_acme-challenge` TXT record, and writes `cert.pem` + `key.pem` into `./certs/`.
- On Windows, run it from Git Bash or WSL.
- This path does not require ports `80/443`, but it does require DNS TXT record access and manual renewal when the certificate expires.

#### If none of the above applies

- If `./certs/` is empty, Caddy falls back to its normal behavior:
  - public hostnames: automatic HTTPS
  - local/private hostnames: internal/self-signed TLS
- If ports `80/443` are not available and you do not have a cert/key pair or DNS TXT access, you need an external reverse proxy or the existing certificate owner to provide/export the certificate and private key.

### Start Script Options

Use these `sekant_server.sh` options after the initial install when you need to operate the Management Console differently:

#### Stop Management Console

```bash
bash sekant_server.sh --stop
```

- Stops the Management Console.
- Keeps your existing setup and stored data.

#### Start Management Console

```bash
bash sekant_server.sh --start
```

- Starts the Management Console.
- If it was not previously stopped, the script falls back to the install flow.

#### Re-run setup prompts

```bash
bash sekant_server.sh --install --reconfigure
```

- Re-prompts for hostname, ports, admin email, and database setup values.
- Keeps existing data unless you manually remove the current installation data.

#### Notes

- Use only one of `--install`, `--start`, or `--stop` at a time.
- `--reconfigure` is only valid with install mode.

### Upgrade

To force an upgrade, update the distribution files and restart using the latest available version:

```bash
bash sekant_server.sh --upgrade
```
