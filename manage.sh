#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUTH_DIR="$SCRIPT_DIR/auth"
AUTH_FILE="$AUTH_DIR/htpasswd"

usage() {
    cat <<'EOF'
Usage:
  ./manage.sh createuser <username>
  ./manage.sh deleteuser <username>
  ./manage.sh listusers
  ./manage.sh restart
EOF
}

require_username() {
    local username="${1:-}"

    if [[ -z "$username" || "$username" == *:* || "$username" =~ [[:space:]] ]]; then
        printf 'Username must be non-empty and contain no spaces or colons.\n' >&2
        exit 1
    fi

    printf '%s' "$username"
}

cmd_gen_certificates() {
    CERTDIR="./certs/labadmin"
    echo "$CERTDIR"
    if [ -d "$CERTDIR" ]; then sudo rm -Rf "$CERTDIR"; fi
    mkdir -p "$CERTDIR"
    openssl genpkey -algorithm RSA -out "$CERTDIR/privkey.pem"
    openssl req -new \
        -key "$CERTDIR/privkey.pem" \
        -out "$CERTDIR/cert.csr" \
        -subj "/C=BR/ST=Goiás/L=Goiânia/O=linf/OU=linf/CN=linf/emailAddress=sinfgo.sptc@gmail.com"
    openssl x509 -req -days 365 -in "$CERTDIR/cert.csr" -signkey "$CERTDIR/privkey.pem" -out "$CERTDIR/fullchain.pem"
}

create_user() {
    local username password confirmation entry temporary
    username="$(require_username "${1:-}")"

    read -r -s -p "Password for $username: " password
    printf '\n'
    read -r -s -p "Confirm password: " confirmation
    printf '\n'

    if [[ "$password" != "$confirmation" ]]; then
        printf 'Passwords do not match.\n' >&2
        exit 1
    fi

    mkdir -p "$AUTH_DIR"
    touch "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"

    entry="$(printf '%s' "$password" | docker run --rm -i --entrypoint htpasswd httpd:2-alpine -Bbn -i "$username")"
    temporary="$(mktemp "$AUTH_FILE.tmp.XXXXXX")"
    chmod 600 "$temporary"
    awk -F: -v user="$username" '$1 != user' "$AUTH_FILE" > "$temporary"
    printf '%s\n' "$entry" >> "$temporary"
    mv "$temporary" "$AUTH_FILE"
    printf 'User %s created. Restart the registry to apply the change.\n' "$username"
}

delete_user() {
    local username temporary
    username="$(require_username "${1:-}")"

    if [[ ! -f "$AUTH_FILE" ]]; then
        printf 'No users exist.\n'
        return
    fi

    temporary="$(mktemp "$AUTH_FILE.tmp.XXXXXX")"
    chmod 600 "$temporary"
    awk -F: -v user="$username" '$1 != user' "$AUTH_FILE" > "$temporary"
    mv "$temporary" "$AUTH_FILE"
    printf 'User %s deleted. Restart the registry to apply the change.\n' "$username"
}

case "${1:-}" in
    createuser)
        create_user "${2:-}"
        ;;
    deleteuser)
        delete_user "${2:-}"
        ;;
    listusers)
        if [[ -f "$AUTH_FILE" ]]; then
            cut -d: -f1 "$AUTH_FILE"
        fi
        ;;
    restart)
        docker compose -f "$SCRIPT_DIR/docker-compose.yaml" restart registry
        ;;
     gen-certificates)
        cmd_gen_certificates
    ;;
    *)
        usage
        exit 1
        ;;
esac
