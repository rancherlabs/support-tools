#!/usr/bin/env bash
set -u

FAIL=0
WARN=0

pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*"; WARN=$((WARN+1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
info() { echo "[INFO] $*"; }

check_service_enabled_or_active() {
  local svc="$1"
  systemctl list-unit-files "$svc" >/dev/null 2>&1 || return 1
  systemctl is-enabled "$svc" >/dev/null 2>&1 || systemctl is-active "$svc" >/dev/null 2>&1
}

echo "RKE2 pre-join host networking checker"
echo "====================================="

# firewalld
if systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
  if systemctl is-active --quiet firewalld.service; then
    fail "firewalld is active. RKE2 docs recommend disabling it."
    echo "       Suggested: systemctl disable --now firewalld"
  else
    pass "firewalld is installed but not active."
  fi
else
  pass "firewalld is not installed."
fi

# NetworkManager
if systemctl list-unit-files NetworkManager.service >/dev/null 2>&1; then
  if systemctl is-active --quiet NetworkManager.service; then
    info "NetworkManager is active."

    NM_CONF_MATCH="$(grep -RhsE 'unmanaged-devices=.*(flannel\*|cali\*|tunl\*|vxlan\.calico|wireguard\.cali)' /etc/NetworkManager/conf.d /usr/lib/NetworkManager/conf.d 2>/dev/null || true)"

    if [[ -n "$NM_CONF_MATCH" ]]; then
      pass "NetworkManager has unmanaged-device rules for RKE2/Canal interfaces."
    else
      fail "NetworkManager does not appear configured to ignore RKE2/Canal interfaces."
      cat <<'EOF'
       Suggested file: /etc/NetworkManager/conf.d/rke2-canal.conf

       [keyfile]
       unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali

       Then run:
       systemctl reload NetworkManager

       If RKE2 is already installed, reboot the node after applying this.
EOF
    fi
  else
    pass "NetworkManager is installed but not active."
  fi
else
  pass "NetworkManager is not installed."
fi

# nm-cloud-setup
for svc in nm-cloud-setup.service nm-cloud-setup.timer; do
  if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
    if check_service_enabled_or_active "$svc"; then
      fail "$svc is enabled or active. RKE2 docs recommend disabling nm-cloud-setup services when present."
      echo "       Suggested: systemctl disable --now $svc"
    else
      pass "$svc exists but is disabled/inactive."
    fi
  fi
done

# sysctl forwarding
ipv4_forward="$(sysctl -n net.ipv4.conf.all.forwarding 2>/dev/null || echo unknown)"
if [[ "$ipv4_forward" == "1" ]]; then
  pass "IPv4 forwarding is enabled."
else
  fail "IPv4 forwarding is not enabled: net.ipv4.conf.all.forwarding=$ipv4_forward"
  echo "       Suggested: echo 'net.ipv4.conf.all.forwarding=1' >/etc/sysctl.d/90-rke2.conf && sysctl --system"
fi

if [[ -e /proc/sys/net/ipv6/conf/all/forwarding ]]; then
  ipv6_forward="$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo unknown)"
  if [[ "$ipv6_forward" == "1" ]]; then
    pass "IPv6 forwarding is enabled."
  else
    warn "IPv6 forwarding is not enabled. Required only for dual-stack IPv6 clusters."
  fi
fi

# iptables / xtables
if command -v iptables >/dev/null 2>&1; then
  pass "iptables binary is present: $(command -v iptables)"
else
  fail "iptables binary is missing. Canal hostPort/portmap can fail without iptables or xtables-nft."
  echo "       Suggested: install iptables or xtables-nft package."
fi

# kernel modules
for mod in br_netfilter overlay; do
  if lsmod | awk '{print $1}' | grep -qx "$mod"; then
    pass "Kernel module loaded: $mod"
  else
    warn "Kernel module not currently loaded: $mod"
    echo "       Suggested: modprobe $mod"
  fi
done

# VXLAN support
if lsmod | awk '{print $1}' | grep -qx vxlan; then
  pass "Kernel module loaded: vxlan"
else
  warn "vxlan module is not currently loaded. This may be required for VXLAN-based CNIs."
  echo "       Suggested: modprobe vxlan"
fi

# bridge netfilter sysctls
for key in net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables; do
  value="$(sysctl -n "$key" 2>/dev/null || echo missing)"
  if [[ "$value" == "1" ]]; then
    pass "$key=1"
  elif [[ "$value" == "missing" ]]; then
    warn "$key is missing. br_netfilter may not be loaded."
  else
    warn "$key=$value"
    echo "       Suggested: sysctl -w $key=1"
  fi
done

echo
echo "Summary"
echo "======="
echo "FAIL: $FAIL"
echo "WARN: $WARN"

if [[ "$FAIL" -gt 0 ]]; then
  echo "Result: NOT READY for RKE2 join."
  exit 2
elif [[ "$WARN" -gt 0 ]]; then
  echo "Result: READY WITH WARNINGS."
  exit 1
else
  echo "Result: READY."
  exit 0
fi
