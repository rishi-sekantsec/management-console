# Installation Manual

## 1) Clone this repo for the release

Run this in an empty folder (the `.` at the end clones into the current directory):

```bash
git clone --branch 1.1.2 --depth 1 https://github.com/rishi-sekantsec/management-console .
```

## 2) Start the installer

```bash
bash start.sh
```

## 3) Fill the prompted setup values

- Domain / Hostname for Management Console (default: localhost)
- Dashboard HTTPS host port (default: 443)
- Event Logging Port (default: 31415)
- Admin email
- Admin username is fixed: admin
- Admin password (default: admin@12345)
- Database setup: local or remote
- Data retention days (default: 700)
- If remote DB: S3 endpoint base, S3 bucket, optional prefix, optional region, access key id, secret access key

# How To Use Features

## Alert + Channels setup

### Create a notification channel

1. Go to **Admin → Operations → Channels** (`/admin/channels`).
2. Click **Add**.
3. Choose a channel method (Email/Slack/Discord/Telegram/Splunk/Custom HTTP).
4. Fill the required fields for that method and keep the channel **Enabled**.
5. Save.

### Create an alert rule and attach channels

1. Go to **Admin → Operations → Alerts** (`/admin/alerts`).
2. Click **Create Alert Rule**.
3. Define the alert logic (filters/SQL), severity, and schedule (if applicable).
4. Attach one or more channels created above.
5. Use **Test** (if available) to confirm delivery, then save the rule.

## Extension options publishing (Deploy from Hosted JSON)

This workflow is used to generate extension options/license JSON and publish it as a public JSON endpoint.

### A) Generate the options JSON

1. Go to **Admin → System → Extension Options** (`/admin/extension-options`).
2. Fill the required fields in the embedded Extension Options page.
3. Generate/Save the options JSON.
4. The platform stores the latest generated payload and updates the system hosted JSON payload at **`/test-license`**.

### B) Publish it via Hosted JSON

1. Go to **Admin → Operations → Hosted JSON** (`/admin/hosted-json`).
2. Click **Add Hosted JSON** and create an endpoint path (example: `licenses/customer-a`).
3. Click **Deploy** and select your target endpoint.
   - This overwrites that endpoint payload with the current **`/test-license`** payload.
4. Click **Copy URL** and share the public URL (served under `/public-json/<path>`).

## User creation workflow

1. Go to **Admin → Access Control → Users** (`/admin/users`).
2. Click **Create User**.
3. Follow the wizard:
   - **Username + Password**: username must be at least 5 characters and use only lowercase letters and underscores.
   - **Profile**: email (required), first name, last name, Active toggle.
   - **Access**: assign a Primary Role (optional) and add the user to Groups (recommended for shared permissions).
   - **Notifications (optional)**: add Slack/Discord/Telegram identifiers for alert delivery.
   - **Review**: confirm values and create.
4. After creation, open the user record to verify effective access and notification metadata.

## OIDC setup process

The login page uses SSO. Users must exist in Sekant (by email) before they can sign in.

1. Go to **Admin → System → Settings** (`/admin/settings`).
2. Open the **SSO (OIDC)** tab.
3. Choose a provider to configure (Google / Microsoft / Okta).
4. Copy the **Redirect URI** shown in the UI and add it to your provider application configuration.
5. Fill in the provider values and enable it:
   - **Google**: Client ID, Client Secret
   - **Microsoft**: Tenant ID, Client ID, Client Secret
   - **Okta**: Issuer, Client ID, Client Secret
6. Click **Save** for that provider.
7. Create (or update) the matching user in **Admin → Users** with the same email, then test login from `/login`.
