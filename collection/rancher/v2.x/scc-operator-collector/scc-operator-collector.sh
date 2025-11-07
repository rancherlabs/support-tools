#!/usr/bin/env bash

# SCC Operator Support Bundle Collector
# Collects diagnostic information for troubleshooting the SUSE Customer Center Operator

set -e

# Default values
REDACT=true
OUTPUT_FORMAT="tar"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BUNDLE_NAME="scc-support-bundle-${TIMESTAMP}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-cattle-scc-system}"
LEASE_NAMESPACE="${LEASE_NAMESPACE:-kube-system}"
OPERATOR_NAME="rancher-scc-operator"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Collect diagnostic information for the SCC Operator into a support bundle.

OPTIONS:
    --no-redact              Disable redaction of sensitive information in secrets.
                             This will force folder output and convert secret data to readable stringData.
                             (WARNING: Bundle will contain sensitive data)
    --output <folder|tar>    Output format (default: tar)
                             - folder: Create a directory with collected files
                             - tar: Create a compressed tar.gz archive
    --namespace <namespace>  Operator namespace (default: cattle-scc-system)
    --lease-namespace <ns>   Lease namespace (default: kube-system)
    --name <name>            Custom bundle name (default: scc-support-bundle-<timestamp>)
    -h, --help               Show this help message

EXAMPLES:
    # Collect support bundle with default settings (specific fields redacted, tar.gz output)
    $(basename "$0")

    # Collect bundle without redaction (for local debugging only, forces folder output)
    $(basename "$0") --no-redact

    # Create a folder bundle for local inspection
    $(basename "$0") --output folder

SECURITY NOTES:
    - By default, specific sensitive fields in secrets are redacted.
    - Use --no-redact only for local debugging.
    - When --no-redact is used, output is automatically forced to 'folder' for security.

EOF
    exit 1
}

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-redact)
            REDACT=false
            shift
            ;;
        --output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --namespace)
            OPERATOR_NAMESPACE="$2"
            shift 2
            ;;
        --lease-namespace)
            LEASE_NAMESPACE="$2"
            shift 2
            ;;
        --name)
            BUNDLE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate output format
if [[ "$OUTPUT_FORMAT" != "folder" && "$OUTPUT_FORMAT" != "tar" ]]; then
    log_error "Invalid output format: $OUTPUT_FORMAT. Must be 'folder' or 'tar'"
    exit 1
fi

# Security check: if --no-redact is used, force folder output
if [[ "$REDACT" == "false" && "$OUTPUT_FORMAT" == "tar" ]]; then
    log_warn "The --no-redact flag is being used, which contains sensitive data."
    log_warn "Forcing output to 'folder' format for security purposes."
    OUTPUT_FORMAT="folder"
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl and try again."
    exit 1
fi

# Check if jq and yq are available for redaction
if [[ "$REDACT" == "true" ]] && ! command -v yq &> /dev/null && ! command -v jq &> /dev/null; then
    log_warn "jq or yq not found. Secret redaction will be more aggressive and less specific."
    log_warn "Install both jq and yq for selective redaction of secret fields."
    if ! command -v jq &> /dev/null; then
      log_warn "jq is missing or not in PATH env"
    fi
    if ! command -v yq &> /dev/null; then
      log_warn "yq is missing or not in PATH env"
    fi
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

# Create bundle directory
BUNDLE_DIR="${BUNDLE_NAME}"
log_info "Creating support bundle directory: ${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}"

# Redaction/Transformation function for secrets
redact_secret() {
    local input_file="$1"
    local secret_name="$2"

    if [[ "$REDACT" == "false" ]]; then
        # When not redacting, convert data to stringData for readability if yq is available
        if command -v yq &> /dev/null; then
            # This expression moves .data to .stringData and base64-decodes the values.
            # The '// .' ensures that files that are not secrets or have no .data field are passed through unchanged.
            yq eval '(select(.kind == "Secret" and .data) | .stringData = .data | del(.data) | .stringData |= with_entries(.value |= @base64d)) // .' "$input_file"
        else
            log_warn "yq not found, cannot convert secret data to stringData for readability. Secret data will remain base64 encoded."
            cat "$input_file"
        fi
        return
    fi

    if ! command -v jq &> /dev/null && ! command -v yq &> /dev/null; then
        log_warn "jq and/or yq not found, falling back to basic (full) redaction for secret '$secret_name'."
        # Fallback: use sed for basic redaction
        sed -E 's/(^\s+[a-zA-Z0-9_-]+:).*/\1 REDACTED/' "$input_file"
        return
    fi

    local keys_to_redact=()
    if [[ "$secret_name" == "scc-registration" || "$secret_name" =~ ^registration-code- ]]; then
        keys_to_redact+=("regCode")
    elif [[ "$secret_name" =~ ^scc-system-credentials- ]]; then
        keys_to_redact+=("password")
    fi

    if [[ ${#keys_to_redact[@]} -gt 0 ]]; then
      local key_conditions=""
      for key in "${keys_to_redact[@]}"; do
          [[ -n "$key_conditions" ]] && key_conditions+=" or "
          key_conditions+=".key == \"${key}\""
      done

      yq eval -o=json "$input_file" \
        | jq --arg cond "$key_conditions" '
            .data |= with_entries(
              if ('"$key_conditions"') then .value = "[REDACTED]" else . end
            )
          ' \
        | yq eval -P -
    else
        # If no specific keys are targeted for redaction for this secret,
        # we pass it through unmodified.
        cat "$input_file"
    fi
}

# Function to collect cluster information
collect_cluster_info() {
    log_info "Collecting cluster information..."
    local output_dir="${BUNDLE_DIR}/cluster-info"
    mkdir -p "$output_dir"

    kubectl version --output=yaml > "${output_dir}/version.yaml" 2>&1 || true
    kubectl cluster-info > "${output_dir}/cluster-info.txt" 2>&1 || true
    kubectl get nodes -o wide > "${output_dir}/nodes.txt" 2>&1 || true
    kubectl get nodes -o yaml > "${output_dir}/nodes.yaml" 2>&1 || true
}

# Function to collect Registration CRDs
collect_registrations() {
    log_info "Collecting Registration CRDs..."
    local output_dir="${BUNDLE_DIR}/registrations"
    mkdir -p "$output_dir"

    # List all registrations
    kubectl get registrations.scc.cattle.io -A -o wide > "${output_dir}/registrations-list.txt" 2>&1 || true

    # Get detailed YAML for each registration
    local registrations=$(kubectl get registrations.scc.cattle.io -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$registrations" ]]; then
        for reg in $registrations; do
            log_info "  - Collecting registration: $reg"
            kubectl get registration.scc.cattle.io "$reg" -o yaml > "${output_dir}/registration-${reg}.yaml" 2>&1 || true
            kubectl describe registration.scc.cattle.io "$reg" > "${output_dir}/registration-${reg}-describe.txt" 2>&1 || true
        done
    else
        log_warn "No Registration resources found"
        echo "No registrations found" > "${output_dir}/no-registrations.txt"
    fi
}

# Function to collect secrets
collect_secrets() {
    log_info "Collecting secrets from namespace: ${OPERATOR_NAMESPACE}..."
    local output_dir="${BUNDLE_DIR}/secrets"
    mkdir -p "$output_dir"

    # Secret patterns to collect
    local secret_patterns=(
        "scc-registration"
        "rancher-registration"
        "scc-system-credentials-"
        "registration-code-"
        "offline-request-"
        "offline-certificate-"
        "rancher-scc-metrics"
    )

    # Collect secrets matching patterns
    for pattern in "${secret_patterns[@]}"; do
        local secrets=$(kubectl get secrets -n "$OPERATOR_NAMESPACE" -o jsonpath="{.items[?(@.metadata.name matches \"^${pattern}\")].metadata.name}" 2>/dev/null || echo "")

        if [[ -n "$secrets" ]]; then
            for secret in $secrets; do
                log_info "  - Collecting secret: $secret"
                local secret_file="${output_dir}/secret-${secret}.yaml"
                kubectl get secret "$secret" -n "$OPERATOR_NAMESPACE" -o yaml > "$secret_file" 2>&1 || true

                # Apply redaction or transformation
                local temp_file="${secret_file}.tmp"
                redact_secret "$secret_file" "$secret" > "$temp_file"
                mv "$temp_file" "$secret_file"
            done
        fi
    done

    # List all secrets in the namespace for reference
    kubectl get secrets -n "$OPERATOR_NAMESPACE" -o wide > "${output_dir}/secrets-list.txt" 2>&1 || true

    if [[ "$REDACT" == "true" ]]; then
        echo "NOTE: Specific sensitive fields in secrets have been redacted for security." > "${output_dir}/REDACTED.txt"
    else
        echo "WARNING: This bundle contains UNREDACTED secret data" > "${output_dir}/UNREDACTED-WARNING.txt"
    fi
}

# Function to collect ConfigMaps
collect_configmaps() {
    log_info "Collecting ConfigMaps from namespace: ${OPERATOR_NAMESPACE}..."
    local output_dir="${BUNDLE_DIR}/configmaps"
    mkdir -p "$output_dir"

    # Collect operator config
    kubectl get configmap "scc-operator-config" -n "$OPERATOR_NAMESPACE" -o yaml > "${output_dir}/scc-operator-config.yaml" 2>&1 || true

    # List all configmaps
    kubectl get configmaps -n "$OPERATOR_NAMESPACE" -o wide > "${output_dir}/configmaps-list.txt" 2>&1 || true
}

# Function to collect operator pods
collect_operator_pods() {
    log_info "Collecting operator pod information from namespace: ${OPERATOR_NAMESPACE}..."
    local output_dir="${BUNDLE_DIR}/operator-pods"
    mkdir -p "$output_dir"

    # List all pods
    kubectl get pods -n "$OPERATOR_NAMESPACE" -o wide > "${output_dir}/pods-list.txt" 2>&1 || true

    # Get pods with operator label
    local pods=$(kubectl get pods -n "$OPERATOR_NAMESPACE" -l "app.kubernetes.io/name=${OPERATOR_NAME}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$pods" ]]; then
        for pod in $pods; do
            log_info "  - Collecting pod: $pod"

            # Get pod details
            kubectl get pod "$pod" -n "$OPERATOR_NAMESPACE" -o yaml > "${output_dir}/pod-${pod}.yaml" 2>&1 || true
            kubectl describe pod "$pod" -n "$OPERATOR_NAMESPACE" > "${output_dir}/pod-${pod}-describe.txt" 2>&1 || true

            # Get current logs
            log_info "    - Collecting current logs for pod: $pod"
            kubectl logs "$pod" -n "$OPERATOR_NAMESPACE" --all-containers=true > "${output_dir}/pod-${pod}-logs.txt" 2>&1 || true

            # Get previous logs if available
            log_info "    - Collecting previous logs for pod: $pod (if available)"
            kubectl logs "$pod" -n "$OPERATOR_NAMESPACE" --previous --all-containers=true > "${output_dir}/pod-${pod}-logs-previous.txt" 2>&1 || true
        done
    else
        log_warn "No operator pods found with label app.kubernetes.io/name=${OPERATOR_NAME}"
        echo "No operator pods found" > "${output_dir}/no-pods.txt"
    fi
}

# Function to collect leases (for leader election info)
collect_leases() {
    log_info "Collecting lease information from namespace: ${LEASE_NAMESPACE}..."
    local output_dir="${BUNDLE_DIR}/leases"
    mkdir -p "$output_dir"

    # List all leases
    kubectl get leases -n "$LEASE_NAMESPACE" -o wide > "${output_dir}/leases-list.txt" 2>&1 || true

    # Get operator-specific lease
    kubectl get lease "${OPERATOR_NAME}" -n "$LEASE_NAMESPACE" -o yaml > "${output_dir}/lease-${OPERATOR_NAME}.yaml" 2>&1 || true
    kubectl describe lease "${OPERATOR_NAME}" -n "$LEASE_NAMESPACE" > "${output_dir}/lease-${OPERATOR_NAME}-describe.txt" 2>&1 || true
}

# Function to collect events
collect_events() {
    log_info "Collecting events from namespace: ${OPERATOR_NAMESPACE}..."
    local output_dir="${BUNDLE_DIR}/events"
    mkdir -p "$output_dir"

    # Get events from operator namespace
    kubectl get events -n "$OPERATOR_NAMESPACE" --sort-by='.lastTimestamp' > "${output_dir}/events-${OPERATOR_NAMESPACE}.txt" 2>&1 || true

    # Get events from lease namespace if different
    if [[ "$LEASE_NAMESPACE" != "$OPERATOR_NAMESPACE" ]]; then
        kubectl get events -n "$LEASE_NAMESPACE" --sort-by='.lastTimestamp' > "${output_dir}/events-${LEASE_NAMESPACE}.txt" 2>&1 || true
    fi

    # Get all events (for wider context)
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "${output_dir}/events-all-namespaces.txt" 2>&1 || true
}

# Function to collect CRD definition
collect_crd() {
    log_info "Collecting Registration CRD definition..."
    local output_dir="${BUNDLE_DIR}/crds"
    mkdir -p "$output_dir"

    kubectl get crd registrations.scc.cattle.io -o yaml > "${output_dir}/registrations.scc.cattle.io.yaml" 2>&1 || true
    kubectl describe crd registrations.scc.cattle.io > "${output_dir}/registrations.scc.cattle.io-describe.txt" 2>&1 || true
}

# Function to create metadata file
create_metadata() {
    log_info "Creating metadata file..."
    local metadata_file="${BUNDLE_DIR}/metadata.txt"
    local redaction_note="Unredacted"
    if [[ "$REDACT" == "true" ]]; then
        redaction_note="Specific fields redacted"
    fi

    cat > "$metadata_file" <<EOF
SCC Operator Support Bundle
===========================

Collection Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Bundle Name: ${BUNDLE_NAME}
Redaction Status: ${redaction_note}
Output Format: ${OUTPUT_FORMAT}

Operator Configuration:
- Operator Namespace: ${OPERATOR_NAMESPACE}
- Lease Namespace: ${LEASE_NAMESPACE}
- Operator Name: ${OPERATOR_NAME}

Kubernetes Cluster:
$(kubectl version --short 2>/dev/null || kubectl version 2>/dev/null)

Current Context:
$(kubectl config current-context 2>/dev/null || echo "Unable to determine")

Collected Resources:
- Registration CRDs
- Secrets (${redaction_note})
- ConfigMaps
- Operator Pods and Logs
- Leases
- Events
- CRD Definitions

EOF

    if [[ "$REDACT" == "false" ]]; then
        cat >> "$metadata_file" <<EOF

!!! SECURITY WARNING !!!
=======================
This support bundle contains UNREDACTED secret data.
Do NOT share this bundle externally.
Only use for local debugging purposes.

EOF
    fi
}

# Main collection process
main() {
    log_info "Starting SCC Operator support bundle collection..."
    log_info "Bundle name: ${BUNDLE_NAME}"
    log_info "Redaction: ${REDACT}"
    log_info "Output format: ${OUTPUT_FORMAT}"
    echo ""

    # Collect all diagnostic information
    collect_cluster_info
    collect_crd
    collect_registrations
    collect_secrets
    collect_configmaps
    collect_operator_pods
    collect_leases
    collect_events
    create_metadata

    # Handle output format
    if [[ "$OUTPUT_FORMAT" == "tar" ]]; then
        log_info "Creating compressed archive..."
        tar -czf "${BUNDLE_NAME}.tar.gz" "${BUNDLE_DIR}"
        rm -rf "${BUNDLE_DIR}"
        log_info "${GREEN}Support bundle created successfully: ${BUNDLE_NAME}.tar.gz${NC}"
        echo ""
        log_info "You can share this file with SUSE support for troubleshooting."
    else
        log_info "${GREEN}Support bundle created successfully: ${BUNDLE_DIR}/${NC}"
        echo ""
        if [[ "$REDACT" == "false" ]]; then
            log_warn "This bundle contains UNREDACTED secrets. Do NOT share externally!"
        else
            log_info "You can share this directory with SUSE support for troubleshooting."
        fi
    fi

    echo ""
    log_info "Collection complete!"
}

# Run main function
main
