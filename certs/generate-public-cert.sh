#!/usr/bin/env bash

set -euo pipefail

ACME_IMAGE="${ACME_IMAGE:-neilpang/acme.sh}"
LETSENCRYPT_SERVER="letsencrypt"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
certs_dir="${script_dir}"
acme_dir="${certs_dir}/.acme"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

docker_host_path() {
  local dir="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -am "$dir"
    return 0
  fi

  case "$(uname -s 2>/dev/null || printf '')" in
    MINGW*|MSYS*|CYGWIN*)
      if (cd "$dir" && pwd -W >/dev/null 2>&1); then
        (cd "$dir" && pwd -W)
        return 0
      fi
      ;;
  esac

  (cd "$dir" && pwd -P)
}

run_acme() {
  docker run --rm -it \
    -v "${acme_mount}:/acme.sh" \
    "$ACME_IMAGE" "$@"
}

wait_for_dns_confirmation() {
  local answer=""
  while true; do
    printf "Type 'continue' once the TXT record is created and visible in DNS: "
    IFS= read -r answer
    answer="$(trim "$answer")"
    if [[ "$(printf "%s" "$answer" | tr '[:upper:]' '[:lower:]')" == "continue" ]]; then
      return 0
    fi
    echo "DNS validation is still paused. Enter exactly 'continue' after the TXT record is live."
  done
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required to generate public certificates." >&2
  exit 1
fi

mkdir -p "$certs_dir" "$acme_dir"
acme_mount="$(docker_host_path "$acme_dir")"
certs_mount="$(docker_host_path "$certs_dir")"

printf "Domain name: "
IFS= read -r domain_input
domain="$(trim "$domain_input")"
if [[ -z "$domain" ]]; then
  echo "Error: domain is required." >&2
  exit 1
fi

printf "Contact email (optional, press Enter to skip): "
IFS= read -r email_input
email="$(trim "$email_input")"

echo
echo "This script uses Let's Encrypt manual DNS challenge."
echo "Ports 80/443 are not required, but you must be able to create the TXT record it prints."
echo
echo "Certificate files will be written to:"
echo "  ${certs_dir}/cert.pem"
echo "  ${certs_dir}/key.pem"
echo

echo "Preparing ACME account..."
if [[ -n "$email" ]]; then
  run_acme --register-account --server "$LETSENCRYPT_SERVER" -m "$email" >/dev/null || true
else
  run_acme --register-account --server "$LETSENCRYPT_SERVER" >/dev/null || true
fi

echo
echo "Step 1/3: Starting manual DNS validation."
echo "Copy the TXT record shown by acme.sh into your DNS provider."
echo
set +e
run_acme \
  --issue \
  --server "$LETSENCRYPT_SERVER" \
  --dns \
  -d "$domain" \
  --yes-I-know-dns-manual-mode-enough-go-ahead-please
issue_status=$?
set -e

if (( issue_status != 0 )); then
  echo
  echo "acme.sh returned after printing the TXT record. This is expected in manual DNS mode."
fi

echo
wait_for_dns_confirmation

echo
echo "Step 2/3: Completing validation with Let's Encrypt."
run_acme \
  --renew \
  --server "$LETSENCRYPT_SERVER" \
  -d "$domain" \
  --yes-I-know-dns-manual-mode-enough-go-ahead-please

echo
echo "Step 3/3: Installing certificate files into the certs folder."
docker run --rm \
  -v "${acme_mount}:/acme.sh" \
  -v "${certs_mount}:/certs" \
  "$ACME_IMAGE" \
  --install-cert \
  -d "$domain" \
  --key-file /certs/key.pem \
  --fullchain-file /certs/cert.pem

echo
echo "Done."
echo "Created files:"
echo "  ${certs_dir}/cert.pem"
echo "  ${certs_dir}/key.pem"
echo
echo "Important:"
echo "  - This certificate is valid for ${domain} only."
echo "  - Open the dashboard using https://${domain} (or that hostname with your custom HTTPS port)."
echo "  - Do not use the EC2 public IP in the browser after installing this cert; browsers will show a certificate mismatch."
echo "  - If the stack was previously configured with a different hostname or the raw IP, re-run bash sekant_server.sh --install --reconfigure and set the hostname to ${domain}."
echo
echo "Restart the stack to have Caddy pick up the new certificate files."
