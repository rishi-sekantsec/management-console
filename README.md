# Installation Manual

## Installation Requirements

- `bash`
- `git`
- `docker`
- `docker compose`
- On Apple Silicon, enable Docker Desktop's `Use Rosetta for x86/amd64 emulation` for any amd64-only Sekant images.

## 0) Create the Installation Directory

```bash
mkdir sekant
cd sekant
```

## 1) Clone the Release Repository

Run this in the empty folder you created above. The `.` at the end clones the repository into the current directory.

```bash
git clone --branch v1.1.11 --depth 1 https://github.com/rishi-sekantsec/management-console .
```

## 2) Start the Installer

```bash
bash start.sh
```

## 3) Post-Installation Checklist

### System Settings

- Log in to the console using the admin credentials.
- Navigate to `Admin > System > Settings`.
- In the `Security Settings` tab, set the `CUSTOMER KEY` if one is available.
- In the `System Settings` tab, set the display timezone.
- In `System Settings`, ensure `Default Security Dashboard Automatic Refresh Interval` is set to `300`.

### Individual Extension Testing

- Navigate to `Admin > System > Settings`.
- Open the `Security Settings` tab.
- Copy the `Event Logging URL` and `Auth Token`.
- On the test device, install the Sekant browser extension from the browser web store.
- Open the extension options by clicking the extension icon and then the gear/settings option.
- Paste the `Event Logging URL` and `Auth Token`.
- Set the required options and save them.

## Appendix

### Upgrade

To force an upgrade, update the distribution files and restart using the latest available version:

```bash
bash start.sh --upgrade
```
