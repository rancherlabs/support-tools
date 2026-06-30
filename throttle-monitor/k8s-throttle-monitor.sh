#!/bin/bash
set -e

# 1. Detect Distribution
if [ -d "/var/lib/rancher/rke2" ]; then
    DISTRO="rke2"
    BASE_DIR="/var/lib/rancher/rke2/server/tls"
elif [ -d "/var/lib/rancher/k3s" ]; then
    DISTRO="k3s"
    BASE_DIR="/var/lib/rancher/k3s/server/tls"
else
    echo "Error: Neither RKE2 nor K3s detected."
    exit 1
fi

echo "Detected Distribution: $DISTRO"

# 2. Component Mapping
# Format: "Name|Port|CertFile|KeyFile"
COMPONENTS=(
    "kube-apiserver|6443|client-admin.crt|client-admin.key"
    "kube-controller-manager|10257|client-admin.crt|client-admin.key"
    "kube-scheduler|10259|client-admin.crt|client-admin.key"
    "kubelet|10250|client-admin.crt|client-admin.key"
)

# 3. Helper Function
get_metrics() {
    local name=$1
    local port=$2
    local cert="$BASE_DIR/$3"
    local key="$BASE_DIR/$4"
    local url="https://127.0.0.1:${port}/metrics"

    # Quick check if endpoint is responding
    if ! curl -s -k --key "$key" --cert "$cert" "$url" | head -n 1 > /dev/null; then
        echo "$name OFF"
        return
    fi

    local raw_data=$(curl -s -k --key "$key" --cert "$cert" "$url")
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
    IFS='|' read -r name port cert key <<< "$comp"
    read -r out_name sum count <<< "$(get_metrics "$name" "$port" "$cert" "$key")"
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
        IFS='|' read -r name port cert key <<< "$comp"
        
        # Skip if it wasn't alive in baseline
        if [ -z "${S1[$name]}" ]; then continue; fi

        read -r out_name sum count <<< "$(get_metrics "$name" "$port" "$cert" "$key")"
        S2["$name"]=$sum
        C2["$name"]=$count
        
        delta_S=$(echo "${S2[$name]} - ${S1[$name]}" | bc)
        delta_C=$(echo "${C2[$name]} - ${C1[$name]}" | bc)

        # Safe guard against zero-division
        if [ -z "$delta_C" ] || [ $(echo "$delta_C == 0" | bc) -eq 1 ]; then
            delta_C=1
        fi

        intensity=$(echo "scale=4; $delta_S / $delta_t" | bc | awk '{printf "%.4f", $0}')
        penalty=$(echo "scale=4; $delta_S / $delta_C" | bc | awk '{printf "%.4f", $0}')

        printf "%-25s %-15s %-15s\n" "$name" "$intensity" "$penalty"

        # Roll the snapshot forward so the next interval calculates from this point
        S1["$name"]="${S2[$name]}"
        C1["$name"]="${C2[$name]}"
    done
    
    t1=$t2
done