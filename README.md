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

:3