# Installation Manual

## 1) Clone this repo for the release

Run this in an empty folder (the `.` at the end clones into the current directory):

```bash
git clone --branch v1.1.6 --depth 1 https://github.com/rishi-sekantsec/management-console .
```

## 2) Start the installer

```bash
bash start.sh
```

## 3) Update / Upgrade

On every startup, `start.sh` checks GitHub for a newer version and prompts whether you want to upgrade.

```bash
bash start.sh
```

To force an upgrade (auto-update distribution files, then restart using the latest version):

```bash
bash start.sh --upgrade
```

If the GitHub repo is private, authenticate for version/update checks:

```bash
GITHUB_TOKEN=<your_token> bash start.sh --upgrade
```
