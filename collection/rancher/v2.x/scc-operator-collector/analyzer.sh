#!/usr/bin/env bash

# SCC Operator Support Bundle Analyzer
# Analyzes a collected support bundle and formats it for human readability.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <bundle_directory>

Analyzes a support bundle created by the collector.sh script.
This script is intended to be run on a workstation with jq and yq installed.

OPTIONS:
    -h, --help               Show this help message

EXAMPLES:
    # Analyze a support bundle directory
    $(basename "$0") scc-support-bundle-20231027-123456
EOF
    exit 1
}

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$BUNDLE_DIR" ]]; then
                BUNDLE_DIR="$1"
            else
                log_error "Unknown option: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$BUNDLE_DIR" ]]; then
    log_error "Bundle directory not specified."
    usage
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
    log_error "Bundle directory not found: $BUNDLE_DIR"
    exit 1
fi

# Check if jq and yq are available
if ! command -v jq &> /dev/null; then
    log_error "jq not found. Please install jq and try again."
    exit 1
fi
if ! command -v yq &> /dev/null; then
    log_error "yq not found. Please install yq and try again."
    exit 1
fi

# Function to process secrets for readability
process_secret() {
    local input_file="$1"
    local secret_name="$2"
    local output_file="$3"

    log_info "  - Processing secret: $secret_name"

    # Base64 decode all data fields and convert to stringData
    local secret_json
    secret_json=$(yq eval '(select(.kind == "Secret" and .data) | .stringData = .data | del(.data) | .stringData |= with_entries(.value |= @base64d)) // .' -o=json "$input_file")

    # Special handling for metrics secret to format the payload
    if [[ "$secret_name" == "rancher-scc-metrics" ]]; then
        # Extract the payload, pretty-print it if it's JSON, and update the secret
        local payload_content
        payload_content=$(echo "$secret_json" | jq -r '.stringData.payload // ""')

        if [[ -n "$payload_content" ]]; then
            local pretty_payload
            # Try to pretty-print; if it's not valid JSON, use the original content
            pretty_payload=$(echo "$payload_content" | jq '.' 2>/dev/null || echo "$payload_content")
            
            # Update the JSON with the new pretty-printed payload string
            secret_json=$(echo "$secret_json" | jq --arg p "$pretty_payload" '.stringData.payload = $p')
        fi
        
        # Convert to YAML, styling the payload as a multi-line literal block
        echo "$secret_json" | yq eval '.stringData.payload style="literal" | .' -P - > "$output_file"
    else
        # For all other secrets, just convert to YAML
        echo "$secret_json" | yq eval -P - > "$output_file"
    fi
}

# Main analysis process
main() {
    log_info "Starting support bundle analysis for: ${BUNDLE_DIR}"
    
    local secrets_dir="${BUNDLE_DIR}/secrets"
    if [[ -d "$secrets_dir" ]]; then
        log_info "Processing secrets..."
        local processed_secrets_dir="${BUNDLE_DIR}/processed-secrets"
        mkdir -p "$processed_secrets_dir"

        for secret_file in "$secrets_dir"/secret-*.yaml; do
            if [[ -f "$secret_file" ]]; then
                local secret_name
                secret_name=$(basename "$secret_file" | sed -e 's/^secret-//' -e 's/\.yaml$//')
                process_secret "$secret_file" "$secret_name" "${processed_secrets_dir}/secret-${secret_name}.yaml"
            fi
        done
    fi

    log_info "${GREEN}Analysis complete! See the 'processed-secrets' directory for readable secrets.${NC}"
}

# Run main function
main
