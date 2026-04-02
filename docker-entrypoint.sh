#!/bin/sh
# docker-entrypoint.sh — apply environment variable overrides to pref.ini,
# then exec the actual command (default: subconverter).

set -e

PREF_INI="/base/pref.ini"
PREF_EXAMPLE="/base/pref.example.ini"

# Bootstrap pref.ini from the example template if it doesn't exist yet
if [ ! -f "$PREF_INI" ]; then
    echo "[entrypoint] pref.ini not found, copying from pref.example.ini"
    cp "$PREF_EXAMPLE" "$PREF_INI"
fi

# ---------------------------------------------------------------------------
# Helper: upsert a key=value line inside a specific [section] of an ini file.
# Usage: set_ini_value <file> <section> <key> <value>
# ---------------------------------------------------------------------------
set_ini_value() {
    local file="$1" section="$2" key="$3" value="$4"

    if grep -qE "^\[${section}\]" "$file"; then
        # Section exists — check whether key already exists inside it
        # (between this section header and the next one)
        awk -v sec="$section" -v k="$key" -v v="$value" '
            BEGIN { in_sec=0; done=0 }
            /^\[/ {
                if (in_sec && !done) {
                    print k "=" v
                    done=1
                }
                in_sec = ($0 == "[" sec "]")
            }
            in_sec && !done && $0 ~ "^" k "=" {
                print k "=" v
                done=1
                next
            }
            { print }
            END {
                if (in_sec && !done) print k "=" v
            }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    else
        # Section does not exist — append it
        printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$file"
    fi
}

# ---------------------------------------------------------------------------
# Apply GITHUB_PROXY
# The C++ code also reads this env var at runtime, so writing it to the ini
# is optional — but doing so makes the effective config visible in /getconfig.
# ---------------------------------------------------------------------------
if [ -n "$GITHUB_PROXY" ]; then
    echo "[entrypoint] Setting proxy_github = $GITHUB_PROXY"
    set_ini_value "$PREF_INI" "common" "proxy_github" "$GITHUB_PROXY"
fi

# ---------------------------------------------------------------------------
# Apply PROXY_CONFIG / PROXY_RULESET / PROXY_SUBSCRIPTION
# ---------------------------------------------------------------------------
if [ -n "$PROXY_CONFIG" ]; then
    echo "[entrypoint] Setting proxy_config = $PROXY_CONFIG"
    set_ini_value "$PREF_INI" "common" "proxy_config" "$PROXY_CONFIG"
fi

if [ -n "$PROXY_RULESET" ]; then
    echo "[entrypoint] Setting proxy_ruleset = $PROXY_RULESET"
    set_ini_value "$PREF_INI" "common" "proxy_ruleset" "$PROXY_RULESET"
fi

if [ -n "$PROXY_SUBSCRIPTION" ]; then
    echo "[entrypoint] Setting proxy_subscription = $PROXY_SUBSCRIPTION"
    set_ini_value "$PREF_INI" "common" "proxy_subscription" "$PROXY_SUBSCRIPTION"
fi

# ---------------------------------------------------------------------------
# Exec the main process (replaces this shell so signals work correctly)
# ---------------------------------------------------------------------------
exec "$@"
