# unblock-ip-from-beta.sh

Unblock an IP address from beta cluster by calculating the necessary IPv4 ranges to exclude from the blocking configuration - basically just [following the steps outlined on wikitech](https://wikitech.wikimedia.org/wiki/Nova_Resource:Deployment-prep/Blocking_and_unblocking), but automating the process and making it easier to use.

I'm not sorry about the in-line Python >:3

## Help
```bash
➜  ./unblock-ip-from-beta.sh --help
Usage: ./unblock-ip-from-beta.sh [OPTIONS] <IPv4_ADDRESS>

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
    ./unblock-ip-from-beta.sh "192.0.2.100"
    ./unblock-ip-from-beta.sh --verbose --prefix "192.0.2.0/24" "192.0.2.100"
    ./unblock-ip-from-beta.sh --dry-run "192.0.2.100"

DESCRIPTION:
    This script automates the process (https://w.wiki/HpBe) of unblocking an
    IP address from the beta cluster blocking configuration by:

    1. Determining the BGP prefix for the IP (via whoisit.sh or --prefix)
    2. Fetching the current blocking ranges from Gerrit
    3. Calculating new ranges that exclude the target prefix
    4. Updating a local copy of the hiera _.yaml file with the new configuration
    5. Prompting the user to review and save the updated _.yaml file in the hiera config
    6. Running 'sudo run-puppet-agent && sudo systemctl reload haproxy' on the relevant hosts

```

## Dependencies
- `ssh` for remote command execution
- `curl` for API requests
- `python3` for IP address manipulation :3

## Install
Just download the script
```bash
curl -O https://raw.githubusercontent.com/theresnotime/unblock-ip-from-beta/main/unblock-ip-from-beta.sh
```

make it executable
```bash
chmod +x unblock-ip-from-beta.sh
```

and then run it with the IP you want to unblock
```bash
./unblock-ip-from-beta.sh --verbose --dry-run "27.0.7.0"
```

## Example Output
```
➜  ./unblock-ip-from-beta.sh --dry-run "27.0.7.0"
[INFO] DRY RUN mode enabled

[INFO] unblock-ip-from-beta - Version 1.2.1
[INFO] Starting unblock process for IP: 27.0.7.0
[OK] SSH connectivity to deployment-mediawiki14.deployment-prep.eqiad1.wikimedia.cloud is OK
[OK] SSH connectivity to deployment-cache-text08.deployment-prep.eqiad1.wikimedia.cloud is OK
[OK] SSH connectivity to deployment-cache-upload08.deployment-prep.eqiad1.wikimedia.cloud is OK
[OK] Hiera config mirror is accessible
[INFO] Running: ssh deployment-mediawiki14.deployment-prep.eqiad1.wikimedia.cloud 'sudo -i bash -c ./whoisit.sh 27.0.7.0'
[OK] BGP prefix retrieved: 27.0.7.0/24
[INFO] Fetching blocked ranges from the hiera config mirror...
[INFO] Searching for IP ranges that include 27.0.7.0/24...
[OK] Found matching range: 27.0.0.0/8
[INFO] Running: ssh deployment-mediawiki14.deployment-prep.eqiad1.wikimedia.cloud 'sudo -i bash -c ./subtractNetworks.py 27.0.0.0/8 27.0.7.0/24'
[INFO] Updating local _.yaml with new ranges and removing old range...
[OK] Updated local _.yaml file
[OK] Unblocking calculation complete

=== Results ===
Original IP: 27.0.7.0
BGP Prefix: 27.0.7.0/24
Blocking Range: 27.0.0.0/8
Replaced with:

    - 27.0.0.0/22
    - 27.0.4.0/23
    - 27.0.6.0/24
    - 27.0.8.0/21
    - 27.0.16.0/20
    - 27.0.32.0/19
    - 27.0.64.0/18
    - 27.0.128.0/17
    - 27.1.0.0/16
    - 27.2.0.0/15
    - 27.4.0.0/14
    - 27.8.0.0/13
    - 27.16.0.0/12
    - 27.32.0.0/11
    - 27.64.0.0/10
    - 27.128.0.0/9
----
Please review the updated local _.yaml file and save it in the "deployment-prep" hiera config
at https://horizon.wikimedia.org/auth/switch/deployment-prep/?next=/project/puppet
and then press Enter to continue


[QUERY] About to run 'sudo run-puppet-agent && sudo systemctl reload haproxy' on deployment-cache-text08. Do you want to proceed? (Y/n) n
[INFO] Skipping deployment-cache-text08...
[QUERY] About to run 'sudo run-puppet-agent && sudo systemctl reload haproxy' on deployment-cache-upload08. Do you want to proceed? (Y/n) n
[INFO] Skipping deployment-cache-upload08...
[QUERY] Do you want to delete the local _.yaml file? (Y/n) y
[INFO] Deleted.

[QUERY] Do you want to delete the local _.bak.yaml file? (Y/n) y
[INFO] Deleted.

[OK] Done :3 🦊
```

:3