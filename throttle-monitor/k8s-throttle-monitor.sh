#!/bin/bash
set -e

# 1. Detect Distribution and Node Type
if [ -d "/var/lib/rancher/rke2/server/tls" ]; then
    DISTRO="rke2"
    BASE_DIR="/var/lib/rancher/rke2/server/tls"
    NODE_TYPE="server"
    CERT="client-admin.crt"
    KEY="client-admin.key"
elif [ -d "/var/lib/rancher/rke2/agent" ]; then
    DISTRO="rke2"
    BASE_DIR="/var/lib/rancher/rke2/agent"
    NODE_TYPE="agent"
    CERT="client-kubelet.crt"
    KEY="client-kubelet.key"
elif [ -d "/var/lib/rancher/k3s/server/tls" ]; then
    DISTRO="k3s"
    BASE_DIR="/var/lib/rancher/k3s/server/tls"
    NODE_TYPE="server"
    CERT="client-admin.crt"
    KEY="client-admin.key"
elif [ -d "/var/lib/rancher/k3s/agent" ]; then
    DISTRO="k3s"
    BASE_DIR="/var/lib/rancher/k3s/agent"
    NODE_TYPE="agent"
    CERT="client-kubelet.crt"
    KEY="client-kubelet.key"
else
    echo "Error: Neither RKE2 nor K3s detected."
    exit 1
fi

echo "Detected Distribution: $DISTRO ($NODE_TYPE)"

# 2. Component Mapping
# Format: "Name|Port|Scheme|CertFile|KeyFile"
if [ "$NODE_TYPE" = "server" ]; then
    COMPONENTS=(
        "kube-apiserver|6443|https|$CERT|$KEY"
        "kube-proxy|10249|http|none|none"
        "kube-controller-manager|10257|https|$CERT|$KEY"
        "kube-scheduler|10259|https|$CERT|$KEY"
        "kubelet|10250|https|$CERT|$KEY"
    )
else
    COMPONENTS=(
        "kube-proxy|10249|http|none|none"
        "kubelet|10250|https|$CERT|$KEY"
    )
fi
# 3. Helper Function
get_metrics() {
    local name=$1
    local port=$2
    local scheme=$3
    local cert="$BASE_DIR/$4"
    local key="$BASE_DIR/$5"
    local url="${scheme}://127.0.0.1:${port}/metrics"

    local raw_data
    if [ "$scheme" = "https" ]; then
        if ! curl -s -k --key "$key" --cert "$cert" "$url" | head -n 1 > /dev/null; then
            echo "$name OFF"
            return
        fi
        raw_data=$(curl -s -k --key "$key" --cert "$cert" "$url")
    else
        if ! curl -s "$url" | head -n 1 > /dev/null; then
            echo "$name OFF"
            return
        fi
        raw_data=$(curl -s "$url")
    fi

    local sum=$(echo "$raw_data" | grep "^rest_client_rate_limiter_duration_seconds_sum" | awk '{sum += $2} END {printf("%.6f\n", sum)}')
    local count=$(echo "$raw_data" | grep "^rest_client_rate_limiter_duration_seconds_count" | awk '{sum += $2} END {printf("%.0f\n", sum)}')

    # Handle empty grep results
    [ -z "$sum" ] && sum="0.000000"
    [ -z "$count" ] && count="0"

    echo "$name $sum $count"
}

declare -A S1 C1 S2 C2

# Initial Baseline Snapshot
echo "Capturing initial baseline..."
for comp in "${COMPONENTS[@]}"; do
    IFS='|' read -r name port scheme cert key <<< "$comp"
    read -r out_name sum count <<< "$(get_metrics "$name" "$port" "$scheme" "$cert" "$key")"
    if [ "$sum" != "OFF" ]; then
        S1["$name"]=$sum
        C1["$name"]=$count
    fi
done

t1=$(date +%s)

echo "Starting continuous monitoring (Press Ctrl+C to stop)..."
echo "------------------------------------------------------------"
printf "%-25s %-15s %-15s\n" "COMPONENT" "INTENSITY (s/s)" "PENALTY (s/req)"
echo "------------------------------------------------------------"

while true; do
    sleep 10
    t2=$(date +%s)
    delta_t=$((t2 - t1))
    
    # Print a timestamp/header for each cycle
    echo -e "\n--- Snapshot taken at $(date +"%H:%M:%S") (Interval: ${delta_t}s) ---"

    for comp in "${COMPONENTS[@]}"; do
        IFS='|' read -r name port scheme cert key <<< "$comp"
        
        # Skip if it wasn't alive in baseline
        if [ -z "${S1[$name]}" ]; then continue; fi

        read -r out_name sum count <<< "$(get_metrics "$name" "$port" "$scheme" "$cert" "$key")"
        S2["$name"]=$sum
        C2["$name"]=$count
        
        delta_S=$(awk "BEGIN {print ${S2[$name]} - ${S1[$name]}}")
        delta_C=$(awk "BEGIN {print ${C2[$name]} - ${C1[$name]}}")

        # Safe guard against zero-division
        if [ -z "$delta_C" ] || [ "$(awk "BEGIN {print ($delta_C == 0) ? 1 : 0}")" -eq 1 ]; then
            delta_C=1
        fi

        intensity=$(awk "BEGIN {printf \"%.4f\", $delta_S / $delta_t}")
        penalty=$(awk "BEGIN {printf \"%.4f\", $delta_S / $delta_C}")

        printf "%-25s %-15s %-15s\n" "$name" "$intensity" "$penalty"

        # Roll the snapshot forward so the next interval calculates from this point
        S1["$name"]="${S2[$name]}"
        C1["$name"]="${C2[$name]}"
    done
    
    t1=$t2
done