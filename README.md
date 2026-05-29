# Installation Manual

## Installation requirements:

- bash
- git
- docker
- docker compose

## 0) Create Directory

```bash
mkdir sekant
cd sekant
```

## 1) Clone this repo for the release

Run this in an empty folder (the `.` at the end clones into the current directory):

```bash
git clone --branch v1.1.8 --depth 1 https://github.com/rishi-sekantsec/management-console .
```

## 2) Start the installer

```bash
bash start.sh
```

## 3) Checklist

### Settings

- Login to Console with admin credentials
- Navigate to Admin > System > Settings
- In "Security Settings" Tab, Set the "CUSTOMER KEY" (if available)
- In "System Settings" Tab, Set the "Display Timezone"
- In "System Settings", ensure "Default Security Dashboard Automatic Refresh Interval" is 300

### Individual Extension Testing 
- Navigate to Admin > System > Settings
- Go to Tab "Security Settings"
- Copy the "Event Logging URL" & "Auth Token"
- On the test device, install Sekant from Browser's Extension Webstore
- Open Options of Sekant Security Extension by clicking the icon (gear)
- Paste the "Event Logging URL" and "Auth Token"
- Set and save the desired options.

## APPENDIX

### Upgrade

To force an upgrade (auto-update distribution files, then restart using the latest version):

```bash
bash start.sh --upgrade
```
