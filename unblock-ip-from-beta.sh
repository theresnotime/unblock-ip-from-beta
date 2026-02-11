#!/bin/bash

# Author: Sammy Fox <https://w.wiki/4RXX>
# License: CC0 1.0 Universal
# Source: https://github.com/theresnotime/unblock-ip-from-beta

set -euo pipefail

# Version
VERSION="1.2.0"

# Configuration
DEPLOYMENT_MEDIAWIKI_HOST="deployment-mediawiki14.deployment-prep.eqiad1.wikimedia.cloud"
DEPLOYMENT_TEXT_CACHE_HOST="deployment-cache-text08.deployment-prep.eqiad1.wikimedia.cloud"
DEPLOYMENT_UPLOAD_CACHE_HOST="deployment-cache-upload08.deployment-prep.eqiad1.wikimedia.cloud"
RELOAD_COMMAND="sudo run-puppet-agent && sudo systemctl reload haproxy"
HIERA_URL="https://raw.githubusercontent.com/wikimedia/cloud-instance-puppet/refs/heads/master/deployment-prep/_.yaml"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/theresnotime/unblock-ip-from-beta/refs/heads/main"
EDIT_PUPPET_URL="https://horizon.wikimedia.org/auth/switch/deployment-prep/?next=/project/puppet"
WIKITECH_HELP_URL="https://wikitech.wikimedia.org/wiki/Nova_Resource:Deployment-prep/Blocking_and_unblocking"
WIKITECH_SHORT_HELP_URL="https://w.wiki/HpBe"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
ORANGE='\033[38;2;255;165;0m'
NC='\033[0m' # No Color

# Flags
VERBOSE=false
DRY_RUN=false

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${YELLOW}[VERBOSE]${NC} $1"
    fi
}

print_flag() {
    # Trans flag colors (foreground)
    T_BLUE="\033[38;2;85;205;252m"
    T_PINK="\033[38;2;247;168;184m"
    T_WHITE="\033[38;2;255;255;255m"
    BOLD="\033[1m"
    T_CLEAR="\033[0m"

    echo -e "${BOLD}${T_BLUE}T${T_PINK}R${T_WHITE}A${T_PINK}N${T_BLUE}S ${T_BLUE}R${T_PINK}I${T_WHITE}G${T_PINK}H${T_BLUE}T${T_WHITE}S ${T_BLUE}:${T_PINK}3${T_CLEAR}"
}

# Function to check for script updates by comparing the current version with the latest version available in the GitHub repository.
check_for_updates() {
    print_info "Checking for script updates..."
    # Get latest version
    LATEST_VERSION=$(curl -s -A "unblock-ip-from-beta script" "$RAW_SCRIPT_URL/unblock-ip-from-beta.sh" | grep -m 1 -oE 'VERSION="[^"]+"' | cut -d'"' -f2)
    # Get latest changelog
    LATEST_CHANGELOG=$(curl -s -A "unblock-ip-from-beta script" "$RAW_SCRIPT_URL/CHANGELOG.md" | awk -v ver="## $LATEST_VERSION" '
       BEGIN { in_section=0 }
       $0 ~ ver { in_section=1; next }
       in_section && /^## / { exit }
       in_section && /^\s*-\s*/ { print }
    ')
    # Make easily comparable ^^
    CURRENT_VERSION_NUM=$(echo "$VERSION" | tr -d '.')
    LATEST_VERSION_NUM=$(echo "$LATEST_VERSION" | tr -d '.')
    if [[ "$VERBOSE" == true ]]; then
        print_verbose "Got version info from $RAW_SCRIPT_URL/unblock-ip-from-beta.sh"
        print_verbose "Current version: $VERSION (numeric: $CURRENT_VERSION_NUM)"
        print_verbose "Latest version: $LATEST_VERSION (numeric: $LATEST_VERSION_NUM)"
        print_verbose "Latest changelog ($LATEST_VERSION):\n$LATEST_CHANGELOG"
    fi
    if [[ "$LATEST_VERSION_NUM" -gt "$CURRENT_VERSION_NUM" ]]; then
        print_info "A new version of the script is available: $LATEST_VERSION (current: $VERSION)"
        # Print the changelog for the new version if available
        if [[ -n "$LATEST_CHANGELOG" ]]; then
            print_info "Changelog for version $LATEST_VERSION:"
            echo "$LATEST_CHANGELOG" | while read -r line; do
                echo -e "  ${GREEN}- ${line#*- }${NC}"
            done
            echo ""
        fi
        echo -ne "${ORANGE}[QUERY]${NC} Do you want to download the latest version? (Y/n) "
        read -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ || -z "$REPLY" ]]; then
            print_info "Downloading latest version..."
            if curl -s -A "unblock-ip-from-beta script" "$RAW_SCRIPT_URL/unblock-ip-from-beta.sh" -o unblock-ip-from-beta-new.sh && [[ -s unblock-ip-from-beta-new.sh ]]; then
                mv unblock-ip-from-beta-new.sh unblock-ip-from-beta.sh
                chmod +x unblock-ip-from-beta.sh
                print_success "Updated to latest version. Please run the script again."
                exit 0
            else
                print_error "Failed to download the latest version. Please try again later or download manually from:"
                echo "$RAW_SCRIPT_URL/unblock-ip-from-beta.sh"
                exit 1
            fi
        else
            print_info "OK :)"
        fi
    else
        print_info "You are using the latest version ($LATEST_VERSION) of the script."
    fi
}

# Function to check if an IP/network is contained within another network
# Usage: check_ip_in_range <container_network> <target_ip_or_network>
# Returns: 0 if contained, 1 if not
check_ip_in_range() {
    local container="$1"
    local target="$2"
    
    python3 -c "
import ipaddress
try:
    network = ipaddress.IPv4Network('$container', strict=False)
    # Try as network first, fall back to address
    try:
        target_obj = ipaddress.IPv4Network('$target', strict=False)
        result = network.supernet_of(target_obj)
    except ValueError:
        target_obj = ipaddress.IPv4Address('$target')
        result = target_obj in network
    print(result)
except:
    print(False)
" 2>/dev/null | grep -q "True"
}

# Function to replace a CIDR range in the YAML file with new ranges
# Usage: replace_range_in_yaml <matching_range> <new_ranges>
# Returns: 0 on success, 1 on failure
replace_range_in_yaml() {
    local matching_range="$1"
    local ranges_to_add="$2"
    
    python3 << EOF
import re
import sys

try:
    # Read the original file
    with open('_.yaml', 'r') as f:
        content = f.read()

    # Back up the original file just in case
    with open('_.bak.yaml', 'w') as f:
        f.write(content)

    # Escape special regex characters in the matching range
    matching_range = r'$matching_range'.replace('.', r'\.').replace('/', r'\/')

    # Pattern to match the line with the CIDR (with or without quotes)
    pattern = r"^(\s*-\s*)['\"]?" + matching_range + r"['\"]?\s*$"

    # Replacement text
    ranges_to_add = r'''$ranges_to_add'''

    # Replace the matching line
    new_content, num_replacements = re.subn(pattern, ranges_to_add, content, flags=re.MULTILINE)

    if num_replacements == 0:
        print(f"Error: Pattern not found in _.yaml file", file=sys.stderr)
        sys.exit(1)
    
    if num_replacements > 1:
        print(f"Warning: Pattern matched {num_replacements} times (expected 1)", file=sys.stderr)

    # Write back to file
    with open('_.yaml', 'w') as f:
        f.write(new_content)

    sys.exit(0)
    
except Exception as e:
    print(f"Error during YAML replacement: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    return $?
}

# Convenience function to handle errors and exit with a message
handle_error_exit() {
    print_error "An error occurred during the script execution (see above for details)"
    echo ""
    echo "We're going to exit now - please follow the guide manually:"
    echo "$WIKITECH_HELP_URL"
    echo ""
    echo "If you think this is a bug, contact https://w.wiki/4RXX"
    echo "with details of what you ran and the output you got."
    echo "Good luck!"
    exit 1
}

# Function to check if a SSH config exists for a given host
check_ssh_config() {
    local host="$1"
    ssh -G "$host" &>/dev/null
}

cleanup_files() {
    # Cleanup _.yaml file if it exists
    if [[ -f _.yaml ]]; then
        echo -ne "${ORANGE}[QUERY]${NC} Do you want to delete the local _.yaml file? (Y/n) "
        read -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ || -z "$REPLY" ]]; then
            rm _.yaml
            print_info "Deleted."
        else
            print_info "Kept."
        fi
    fi

    # Cleanup _.bak.yaml file if it exists
    if [[ -f _.bak.yaml ]]; then
        echo ""
        echo -ne "${ORANGE}[QUERY]${NC} Do you want to delete the local _.bak.yaml file? (Y/n) "
        read -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ || -z "$REPLY" ]]; then
            rm _.bak.yaml
            print_info "Deleted."
        else
            print_info "Kept."
        fi
    fi
}

show_version() {
    echo "$0"
    echo ""
    echo "Version: $VERSION"
    echo "Author: Sammy Fox <https://w.wiki/4RXX>"
    echo "Source: https://github.com/theresnotime/unblock-ip-from-beta"
    cat << EOF

$(print_flag)
EOF
}

check_dependencies() {
    local dependencies=("ssh" "curl" "python3")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "Dependency '$dep' is not installed. Please install it and try again."
            handle_error_exit
        fi
    done
}

# Function to display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <IPv4_ADDRESS>

Unblock an IPv4 address from beta cluster by calculating the necessary ranges
to exclude from blocking configuration.

OPTIONS:
    --help              Show this help message and exit
    --version           Show version information and exit
    --verbose           Enable verbose output for debugging
    --dry-run           Simulate the process without making changes
    --prefix <PREFIX>   Manually specify the BGP prefix (skips whoisit.sh lookup)
    --self-update       Check for script updates and optionally download the latest version

ARGUMENTS:
    IPv4_ADDRESS          The IPv4 address to unblock (required)

EXAMPLE:
    $0 "192.0.2.100"
    $0 --verbose --prefix "192.0.2.0/24" "192.0.2.100"
    $0 --dry-run "192.0.2.100"

DESCRIPTION:
    This script automates the process ($WIKITECH_SHORT_HELP_URL) of unblocking an
    IP address from the beta cluster blocking configuration by:

    1. Determining the BGP prefix for the IP (via whoisit.sh or --prefix)
    2. Fetching the current blocking ranges from Gerrit
    3. Calculating new ranges that exclude the target prefix
    4. Updating a local copy of the hiera _.yaml file with the new configuration
    5. Prompting the user to review and save the updated _.yaml file in the hiera config
    6. Running '$RELOAD_COMMAND' on the relevant hosts

EOF
}

# Validate input
if [[ $# -lt 1 ]]; then
    print_error "Usage: $0 [--verbose] [--dry-run] [--prefix <BGP_PREFIX>] <IPv4_ADDRESS>"
    echo "Run '$0 --help' for more information"
    handle_error_exit
fi

# Parse arguments
IP_ADDRESS=""
BGP_PREFIX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;
        --version)
            show_version
            exit 0
            ;;
        --verbose)
            VERBOSE=true
            print_verbose "Verbose mode enabled"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --self-update)
            check_for_updates
            exit 0
            ;;
        --prefix)
            shift
            BGP_PREFIX="$1"
            print_verbose "BGP prefix provided: $BGP_PREFIX"
            shift
            ;;
        *)
            IP_ADDRESS="$1"
            shift
            ;;
    esac
done

# Check dependencies
check_dependencies

# If dry run is enabled, print a warning at the start
if [[ "$DRY_RUN" == true ]]; then
    print_info "DRY RUN mode enabled"
    echo ""
    sleep 1
fi

if [[ -z "$IP_ADDRESS" ]]; then
    print_error "IPv4_ADDRESS is required"
    print_error "Usage: $0 [--verbose] [--dry-run] [--prefix <BGP_PREFIX>] <IPv4_ADDRESS>"
    echo "Run '$0 --help' for more information"
    handle_error_exit
fi

# wtf even is IPv6 anyway
if [[ "$IP_ADDRESS" == *:* ]]; then
    print_error "IPv6 addresses are not supported by this script."
    handle_error_exit
fi

# Validate IP address format
if ! [[ "$IP_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    print_error "Invalid IP address format: $IP_ADDRESS"
    handle_error_exit
fi

print_info "Starting unblock process for IP: $IP_ADDRESS"

# Check SSH connectivity to each host
for host in "$DEPLOYMENT_MEDIAWIKI_HOST" "$DEPLOYMENT_TEXT_CACHE_HOST" "$DEPLOYMENT_UPLOAD_CACHE_HOST"; do
    print_info "Checking SSH connectivity to $host..."
    if ! check_ssh_config "$host"; then
        print_error "SSH configuration for $host is not accessible. Please ensure you have SSH access to this host."
        handle_error_exit
    fi
    print_success "SSH connectivity to $host is working"
done

# Check if HIERA_URL is accessible
print_info "Checking connectivity to the HIERA_URL..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -A "unblock-ip-from-beta script" "$HIERA_URL")
if [[ "$HTTP_STATUS" != "200" ]]; then
    print_error "Cannot access HIERA_URL: $HIERA_URL (HTTP status: $HTTP_STATUS)"
    handle_error_exit
fi
print_success "HIERA_URL is accessible"

# Step 1: SSH to host and run whoisit.sh to get BGP prefix (if not provided)
if [[ -z "$BGP_PREFIX" ]]; then
    print_info "Connecting to $DEPLOYMENT_MEDIAWIKI_HOST and retrieving BGP prefix..."
    print_verbose "Running: ssh $DEPLOYMENT_MEDIAWIKI_HOST 'sudo -i bash -c ./whoisit.sh $IP_ADDRESS'"
    if [[ "$VERBOSE" == true ]]; then
        SSH_OUTPUT=$(ssh "$DEPLOYMENT_MEDIAWIKI_HOST" "sudo -i bash -c './whoisit.sh $IP_ADDRESS'" 2>&1)
        print_verbose "SSH Output:\n$SSH_OUTPUT"
        BGP_PREFIX=$(echo "$SSH_OUTPUT" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}' | head -1)
    else
        BGP_PREFIX=$(ssh "$DEPLOYMENT_MEDIAWIKI_HOST" "sudo -i bash -c './whoisit.sh $IP_ADDRESS'" 2>/dev/null | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}' | head -1)
    fi

    if [[ -z "$BGP_PREFIX" ]]; then
        print_error "Failed to retrieve BGP prefix from whoisit.sh"
        handle_error_exit
    fi
else
    # Quick check that the IP_ADDRESS is within the provided BGP_PREFIX
    print_verbose "Validating that $IP_ADDRESS is within provided prefix $BGP_PREFIX (mistakes happen..!)"
    if ! check_ip_in_range "$BGP_PREFIX" "$IP_ADDRESS"; then
        print_error "Provided prefix $BGP_PREFIX does not contain IP address $IP_ADDRESS"
        handle_error_exit
    fi
    print_info "Using provided BGP prefix"
    print_verbose "Skipping whoisit.sh step"
fi

print_success "BGP prefix retrieved: $BGP_PREFIX"

# Step 2: Fetch the YAML file from Gerrit and find matching range
print_info "Fetching blocking ranges from Gerrit..."
print_verbose "URL: $HIERA_URL"
HIERA_CONTENT=$(curl -s -A "unblock-ip-from-beta script" "$HIERA_URL" | tail -n +6 | sed '$d')

# Save YAML content to file
echo "$HIERA_CONTENT" > _.yaml
print_verbose "Saved YAML content to _.yaml"

if [[ "$VERBOSE" == true ]]; then
    CONTENT_LINES=$(echo "$HIERA_CONTENT" | wc -l)
    print_verbose "Fetched $CONTENT_LINES lines of YAML content"
fi

if [[ -z "$HIERA_CONTENT" ]]; then
    print_error "Failed to fetch YAML from Gerrit"
    echo $HIERA_CONTENT
    handle_error_exit
fi

# Parse YAML to find matching IP ranges
print_info "Searching for IP ranges that include $BGP_PREFIX..."
MATCHING_RANGE=""

# Extract CIDR blocks from YAML and check if any contain our BGP prefix
RANGES_CHECKED=0
while IFS= read -r line; do
    # Look for CIDR notation lines
    if [[ $line =~ ^[[:space:]]*-[[:space:]]*\'?([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2})\'?[[:space:]]*$ ]]; then
        RANGE="${BASH_REMATCH[1]}"
        ((RANGES_CHECKED++))
        print_verbose "Checking if $BGP_PREFIX is in $RANGE"
        # Check if our BGP_PREFIX is contained in this RANGE
        if check_ip_in_range "$RANGE" "$BGP_PREFIX"; then
            MATCHING_RANGE="$RANGE"
            print_success "Found matching range: $MATCHING_RANGE"
            print_verbose "Match found after checking $RANGES_CHECKED range(s)"
            break
        fi
    fi
done <<< "$HIERA_CONTENT"
if [[ "$VERBOSE" == true ]]; then
    print_verbose "Total ranges checked: $RANGES_CHECKED"
fi

if [[ -z "$MATCHING_RANGE" ]]; then
    print_error "No matching IP range found in Gerrit for $BGP_PREFIX"
    handle_error_exit
fi

# Step 3: SSH to host and run subtractNetworks.py
print_info "Running subtractNetworks.py to calculate allowed ranges..."
print_verbose "Running: ssh $DEPLOYMENT_MEDIAWIKI_HOST 'sudo -i bash -c ./subtractNetworks.py $MATCHING_RANGE $BGP_PREFIX'"
if [[ "$VERBOSE" == true ]]; then
    RESULT=$(ssh "$DEPLOYMENT_MEDIAWIKI_HOST" "sudo -i bash -c './subtractNetworks.py $MATCHING_RANGE $BGP_PREFIX'" 2>&1)
    print_verbose "SSH Output:\n$RESULT"
else
    RESULT=$(ssh "$DEPLOYMENT_MEDIAWIKI_HOST" "sudo -i bash -c './subtractNetworks.py $MATCHING_RANGE $BGP_PREFIX'" 2>/dev/null)
fi

if [[ -z "$RESULT" ]]; then
    print_error "Failed to run subtractNetworks.py"
    handle_error_exit
fi

# Extract CIDR ranges from result
RANGES_TO_ADD=$(echo "$RESULT" | grep -E '^\s*-\s*[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}')

# Update _.yaml by replacing MATCHING_RANGE with RANGES_TO_ADD
print_info "Updating _.yaml with new ranges..."
print_verbose "Replacing $MATCHING_RANGE with calculated ranges"

if ! replace_range_in_yaml "$MATCHING_RANGE" "$RANGES_TO_ADD"; then
    print_error "Failed to update _.yaml file"
    print_error "Manual intervention may be required!"
    echo "Here are the ranges to replace $MATCHING_RANGE with:"
    echo "$RANGES_TO_ADD"
    handle_error_exit
fi

print_success "Updated _.yaml file"

# Step 4: Output result
print_success "Unblocking calculation complete"
echo ""
echo "=== Results ==="
echo "Original IP: $IP_ADDRESS"
echo "BGP Prefix: $BGP_PREFIX"
echo "Blocking Range: $MATCHING_RANGE"
echo "Replaced with:"
echo ""
echo "$RANGES_TO_ADD"
echo "----"
echo "Please review the updated _.yaml file and save it in the \"deployment-prep\" hiera config"
echo "($EDIT_PUPPET_URL)"

# Prompt the user to press enter when done
echo -ne "${ORANGE}Press Enter to continue after you've saved the changes...${NC}"
read -r
echo ""

# Run 'sudo run-puppet-agent && sudo systemctl reload haproxy' on each host
for host in "$DEPLOYMENT_TEXT_CACHE_HOST" "$DEPLOYMENT_UPLOAD_CACHE_HOST"; do
    # Tell the user what is about to happen and ask for confirmation before running the command
    echo -ne "${ORANGE}[QUERY]${NC} About to run '$RELOAD_COMMAND' on $host. Do you want to proceed? (Y/n) "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ || -z "$REPLY" ]]; then
        print_info "Proceeding with $host..."
    else
        print_info "Skipping $host..."
        continue
    fi
    print_info "Running '$RELOAD_COMMAND' on $host..."
    if [[ "$DRY_RUN" == true ]]; then
        print_verbose "DRY RUN: Would run '$RELOAD_COMMAND' on $host"
        continue
    fi
    ssh "$host" "$RELOAD_COMMAND"
    print_success "Commands executed successfully on $host"
done

# Cleanup
cleanup_files

echo ""
print_success "Done :3 🦊"