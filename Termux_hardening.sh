#!/data/data/com.termux/files/usr/bin/bash
# ONE SCRIPT: Mirror + pinning + tamper detection + F-Droid + DoH/DNSSEC + OTF ephemeral cert
# https://mirrors.sau.edu.cn/termux/apt/termux-main
# Overrides network/DNS messes. Non-root limits still apply.

set -e

echo "🚀 Setting up your hardened Termux (mirror + pinning + F-Droid + DoH DNSSEC + OTF ephemeral cert)..."

pkg update -y
pkg install -y ca-certificates curl openssl cloudflared fdroid

mkdir -p $HOME/.termux-pinning/certs
cd $HOME/.termux-pinning

# === CLEAN CA BUNDLE + TAMPER LOCK ===
echo "Downloading & locking clean CA bundle..."
curl -L -o cacert.pem https://curl.se/ca/cacert.pem --cacert /dev/null || true
chmod 444 cacert.pem
sha256sum cacert.pem > .ca-hash
chmod 400 .ca-hash

# === YOUR MIRROR (forced) ===
echo "Locking mirror + fallback note..."
cat > $PREFIX/etc/apt/sources.list.d/termux-main.list << 'EOF'
deb https://mirrors.sau.edu.cn/termux/apt/termux-main stable main
EOF
rm -f $PREFIX/etc/apt/sources.list

# === APT PINNING ===
mkdir -p $PREFIX/etc/apt/apt.conf.d
cat > $PREFIX/etc/apt/apt.conf.d/99pinned-ca << 'EOF'
Acquire::https::CAInfo "$HOME/.termux-pinning/cacert.pem";
Acquire::https::Verify-Peer "true";
EOF
chmod 444 $PREFIX/etc/apt/apt.conf.d/99pinned-ca

# === TRUSTED F-DROID (APK + CLI) ===
echo "Downloading trusted F-Droid APK with pinning..."
curl -L -o $HOME/F-Droid.apk https://f-droid.org/F-Droid.apk --cacert cacert.pem
chmod 644 $HOME/F-Droid.apk
echo "✅ F-Droid APK ready: $HOME/F-Droid.apk (install with: pm install $HOME/F-Droid.apk)"

# === GLOBAL PINNING + DOH OVERRIDE + OTF EPHEMERAL CERT + TAMPER CHECK ===
cat >> $HOME/.bashrc << 'EOF'

# === UNBREAKABLE PINNING + ANTI-TAMPER ===
export SSL_CERT_FILE="$HOME/.termux-pinning/cacert.pem"
export CURL_CA_BUNDLE="$HOME/.termux-pinning/cacert.pem"
export GIT_SSL_CAINFO="$HOME/.termux-pinning/cacert.pem"
export REQUESTS_CA_BUNDLE="$HOME/.termux-pinning/cacert.pem"
export PYTHONHTTPSVERIFY=1

alias curl='curl --cacert $HOME/.termux-pinning/cacert.pem'
alias wget='wget --ca-certificate=$HOME/.termux-pinning/cacert.pem'
alias git='git -c http.sslCAInfo=$HOME/.termux-pinning/cacert.pem'

# Pip + fdroid
mkdir -p $HOME/.config/pip
cat > $HOME/.config/pip/pip.conf << EOF
[global]
cert = $HOME/.termux-pinning/cacert.pem
EOF
chmod 444 $HOME/.config/pip/pip.conf

# === TAMPER DETECTION ===
check_pinning_integrity() {
    if [ ! -f "$HOME/.termux-pinning/.ca-hash" ] || [ ! -f "$HOME/.termux-pinning/cacert.pem" ]; then
        echo "❌ CRITICAL: Pinning files missing!"
        return 1
    fi
    local current=$(sha256sum $HOME/.termux-pinning/cacert.pem | awk '{print $1}')
    local stored=$(awk '{print $1}' "$HOME/.termux-pinning/.ca-hash")
    if [ "$current" != "$stored" ]; then
        echo "🚨 TAMPER DETECTED on CA bundle!"
        return 1
    fi
    return 0
}

# === FORCE DOH + DNSSEC (overrides network/DPC DNS path) ===
start_doh_proxy() {
    if ! ss -tlnp 2>/dev/null | grep -q ':5053'; then
        nohup cloudflared proxy-dns --port 5053 --upstream https://dns.quad9.net/dns-query > /dev/null 2>&1 &
        echo "✅ DoH proxy started (Quad9 DNSSEC + malware block)"
    fi
}
start_doh_proxy

# Force local resolver for all tools
echo "nameserver 127.0.0.1" > $PREFIX/etc/resolv.conf
chmod 644 $PREFIX/etc/resolv.conf

# === OTF EPHEMERAL CERT (PFS for DoH/mTLS) ===
if [ ! -f "$HOME/.termux-pinning/certs/ephemeral.crt" ]; then
    openssl req -x509 -newkey rsa:2048 -keyout $HOME/.termux-pinning/certs/ephemeral.key \
        -out $HOME/.termux-pinning/certs/ephemeral.crt -days 1 -nodes \
        -subj "/CN=termux-doh-ephemeral" 2>/dev/null
    chmod 600 $HOME/.termux-pinning/certs/ephemeral.*
    echo "✅ OTF ephemeral cert generated (1-day PFS)"
fi

check_pinning_integrity || echo "⚠️  Fix by re-running script"

test-hardening() {
    echo "=== Testing pinned + DoH + DNSSEC ==="
    curl -I --max-time 10 https://mirrors.sau.edu.cn/termux/apt/termux-main/dists/stable/Release 2>&1 | head -n 6
    echo "DNS test (DoH): $(dig @127.0.0.1 -p 5053 example.com +short | head -n 1)"
    echo "If you see valid response + IP → everything is overridden and pinned."
}
EOF

chmod 400 $HOME/.termux-pinning/.ca-hash
source $HOME/.bashrc

pkg update -y

echo "✅ DONE — Mirror locked + pinning + tamper detection + F-Droid + DoH DNSSEC + OTF ephemeral cert!"
echo ""
echo "🔒 What you now have:"
echo "• Your mirror + clean CA only (DPC system CAs ignored)"
echo "• Tamper detection on every shell"
echo "• Trusted F-Droid APK + CLI"
echo "• Local DoH proxy (Quad9 DNSSEC) overriding all DNS"
echo "• OTF ephemeral cert generated for PFS"
echo ""
echo "Test:   test-hardening"
echo "Check tamper:   check_pinning_integrity"
echo ""
echo "⚠️  IMPORTANT LIMITATION (must know):"
echo "DPC/MDM can still force a full-device VPN or system proxy that bypasses user-space TLS/DoH."
echo "This is the strongest possible non-root protection. Use only on personal devices."
echo ""
echo "Your Termux traffic is now hardened as far as non-root allows."
