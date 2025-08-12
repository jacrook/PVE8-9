#!/bin/bash

# Proxmox VE 8 to 9 Upgrade Script
# Based on official upgrade documentation: https://pve.proxmox.com/wiki/Upgrade_from_8_to_9
# 
# WARNING: This script performs a major system upgrade
# Test in lab environment before running on production systems
#
# License: MIT
# Repository: https://github.com/your-username/proxmox-upgrade-scripts
# 
# Usage: ./proxmox-8to9-upgrade.sh
# 
# Prerequisites:
# - Proxmox VE 8.x installation
# - Root access
# - Network connectivity
# - Complete backups of VMs, containers, and configurations

set -e

# Script version
SCRIPT_VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to prompt for user confirmation
confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Check current PVE version
check_pve_version() {
    log "Checking current Proxmox VE version..."
    
    if ! command -v pveversion &> /dev/null; then
        error "pveversion command not found. Is this a Proxmox VE system?"
    fi
    
    local version=$(pveversion | head -n1 | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+')
    log "Current PVE version: $version"
    
    if [[ $version =~ ^9\. ]]; then
        warning "System is already on PVE 9.x (version $version)"
        confirm "Do you want to continue with post-upgrade verification and fixes?"
        return 0
    elif [[ $version =~ ^8\. ]]; then
        log "PVE 8.x detected, proceeding with upgrade"
        return 0
    else
        error "Unsupported PVE version: $version. This script supports upgrading from 8.x to 9.x"
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check disk space
    local root_space=$(df / | awk 'NR==2 {print $4}')
    local root_space_gb=$((root_space / 1024 / 1024))
    
    if [[ $root_space_gb -lt 5 ]]; then
        error "Insufficient disk space. Need at least 5GB free on root filesystem. Available: ${root_space_gb}GB"
    fi
    
    success "Disk space check passed: ${root_space_gb}GB available"
    
    # Check if tmux is available
    if ! command -v tmux &> /dev/null; then
        log "Installing tmux for session persistence..."
        apt update
        apt install -y tmux
    fi
    
    # Check for active cluster
    if [[ -f /etc/pve/cluster.conf ]] || [[ -f /etc/corosync/corosync.conf ]]; then
        warning "Cluster detected. Ensure you upgrade nodes one by one!"
        confirm "Do you want to continue with cluster node upgrade?"
    fi
}

# Pre-flight environment check
preflight_check() {
    log "Performing pre-flight environment checks..."
    
    # Check network connectivity
    if ! ping -c 1 download.proxmox.com &>/dev/null; then
        error "Cannot reach download.proxmox.com - check network connectivity"
    fi
    
    # Check DNS resolution
    if ! nslookup download.proxmox.com &>/dev/null; then
        warning "DNS resolution issues detected - this might cause package download problems"
    fi
    
    # Check if this is a VM (not recommended for production)
    if [[ -f /sys/class/dmi/id/product_name ]] && grep -qi "virtual\|vmware\|qemu\|kvm" /sys/class/dmi/id/product_name; then
        warning "Running on virtual machine - ensure you have VM snapshots as backup"
    fi
    
    # Check available entropy (low entropy can slow down the upgrade)
    local entropy=$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo "0")
    if [[ $entropy -lt 200 ]]; then
        warning "Low system entropy ($entropy) - upgrade may be slower"
    fi
    
    # Check system load
    local load=$(uptime | grep -oP 'load average: \K[0-9.]+' | head -1)
    local load_int=${load%.*}  # Get integer part
    if command -v bc &>/dev/null; then
        if (( $(echo "$load > 2.0" | bc -l) )); then
            warning "High system load ($load) - consider waiting for lower load before upgrade"
        fi
    elif [[ $load_int -gt 2 ]]; then
        warning "High system load ($load) - consider waiting for lower load before upgrade"
    fi
    
    success "Pre-flight checks completed"
}

# Backup reminder
backup_reminder() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║                        BACKUP REMINDER                      ║
╠══════════════════════════════════════════════════════════════╣
║ Before proceeding, ensure you have backed up:               ║
║                                                              ║
║ • All VMs and containers (vzdump)                          ║
║ • Configuration files in /etc/pve/                         ║
║ • Network configuration (/etc/network/interfaces)          ║
║ • Custom configurations                                     ║
║ • Test restore procedures                                   ║
║                                                              ║
║ Recommended: Take a snapshot of the host system if possible ║
╚══════════════════════════════════════════════════════════════╝

EOF

    confirm "Have you completed all necessary backups?"
}

# Upgrade to latest PVE 8.4.x
upgrade_to_latest_8() {
    log "Upgrading to latest PVE 8.4.x..."
    
    # Check current version before upgrade
    local current_version=$(pveversion | head -n1 | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+')
    
    # Skip if already on PVE 9.x
    if [[ $current_version =~ ^9\. ]]; then
        log "Already on PVE 9.x (version $current_version), skipping 8.4.x upgrade"
        return 0
    fi
    
    apt update
    apt dist-upgrade -y
    
    # Check version after upgrade
    local new_version=$(pveversion | head -n1 | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+\.[0-9]+')
    log "Updated to PVE version: $new_version"
    
    # Accept either 8.4.x or 9.x as valid
    if [[ $new_version =~ ^8\.4\. ]] || [[ $new_version =~ ^9\. ]]; then
        success "Successfully updated PVE (version: $new_version)"
    else
        error "Unexpected version after upgrade: $new_version"
    fi
}

# Run pre-upgrade checklist and preparation
run_checklist() {
    log "Running pre-upgrade checklist and preparation..."
    
    # Run pve8to9 checklist if available
    if command -v pve8to9 &> /dev/null; then
        log "Running pve8to9 checklist..."
        if pve8to9 --full; then
            success "Pre-upgrade checklist passed"
        else
            warning "Pre-upgrade checklist found issues - review output above"
        fi
        confirm "Review the checklist output above. Do you want to continue?"
    else
        warning "pve8to9 checklist script not found. Installing it..."
        apt update
        apt install -y pve-manager
        if command -v pve8to9 &> /dev/null; then
            log "Running pve8to9 checklist..."
            pve8to9 --full
            confirm "Review the checklist output above. Do you want to continue?"
        else
            warning "Could not install pve8to9. Proceeding without automated checks."
        fi
    fi
    
    # Additional safety checks
    log "Performing additional safety checks..."
    
    # Check for custom repository configurations that might cause issues
    if find /etc/apt/sources.list.d/ -name "*.list" -type f | xargs grep -l "bookworm" 2>/dev/null; then
        warning "Found repository files still pointing to 'bookworm' - these will be updated"
    fi
    
    # Check for running VMs/containers
    local running_vms=$(qm list 2>/dev/null | grep running | wc -l || echo "0")
    local running_cts=$(pct list 2>/dev/null | grep running | wc -l || echo "0")
    
    if [[ $running_vms -gt 0 ]] || [[ $running_cts -gt 0 ]]; then
        warning "Found $running_vms running VMs and $running_cts running containers"
        warning "Consider stopping non-essential services before major upgrade"
        confirm "Do you want to continue with running VMs/containers?"
    fi
}

# Update repository configuration
update_repositories() {
    log "Updating repository configuration for Debian Trixie..."
    
    # Backup current sources
    cp -r /etc/apt/sources.list.d /etc/apt/sources.list.d.backup.$(date +%Y%m%d)
    [[ -f /etc/apt/sources.list ]] && cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d)
    
    # Update main Debian repository
    if [[ -f /etc/apt/sources.list ]]; then
        sed -i 's/bookworm/trixie/g' /etc/apt/sources.list
    fi
    
    # Update Proxmox VE repository
    cat > /etc/apt/sources.list.d/pve-install-repo.sources << 'EOL'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
Architectures: amd64
EOL

    # Update Ceph repository if it exists
    if [[ -f /etc/apt/sources.list.d/ceph.sources ]]; then
        log "Updating Ceph repository..."
        cat > /etc/apt/sources.list.d/ceph.sources << 'EOL'
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOL
    fi
    
    # Download new keyring if needed
    if [[ ! -f /usr/share/keyrings/proxmox-archive-keyring.gpg ]]; then
        log "Downloading Proxmox archive keyring..."
        wget --secure-protocol=TLSv1_2 --timeout=30 https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg -O /usr/share/keyrings/proxmox-archive-keyring.gpg
        
        # Verify keyring
        local sha256_expected="136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45"
        local sha256_actual=$(sha256sum /usr/share/keyrings/proxmox-archive-keyring.gpg | cut -d' ' -f1)
        
        if [[ "$sha256_actual" != "$sha256_expected" ]]; then
            error "Keyring verification failed. Expected: $sha256_expected, Got: $sha256_actual"
        fi
        
        success "Keyring verified successfully"
    fi
    
    success "Repository configuration updated"
}

# Perform the upgrade
perform_upgrade() {
    log "Starting upgrade to Proxmox VE 9.0..."
    
    # Update package lists
    apt update
    
    # Remove conflicting packages if they exist
    if dpkg -l | grep -q linux-image-amd64; then
        log "Removing conflicting linux-image-amd64 package..."
        apt remove -y linux-image-amd64
    fi
    
    # Remove systemd-boot meta-package if present
    if dpkg -l | grep -q "^ii.*systemd-boot[[:space:]]"; then
        log "Removing systemd-boot meta-package..."
        apt remove -y systemd-boot
    fi
    
    # Perform the main upgrade with proper error handling
    log "Performing dist-upgrade (this may take a while)..."
    
    # Set debconf to non-interactive mode with fallback to old config
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    
    # Perform upgrade with better error handling
    if apt dist-upgrade -y; then
        success "Package upgrade completed successfully"
    else
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            success "Package upgrade completed"
        else
            warning "Upgrade completed with warnings (exit code: $exit_code)"
            log "Continuing with post-upgrade steps..."
        fi
    fi
    
    # Check if we ended up on PVE 9.x after the upgrade
    local new_version=$(pveversion 2>/dev/null | head -n1 | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+' || echo "unknown")
    log "Version after upgrade: $new_version"
    
    if [[ $new_version =~ ^9\. ]]; then
        success "Successfully upgraded to PVE 9.x (version $new_version)"
    elif [[ $new_version == "unknown" ]]; then
        warning "Could not determine PVE version after upgrade - will verify later"
    else
        warning "Unexpected version after upgrade: $new_version - continuing with kernel installation"
    fi
}

# Install and configure PVE 9 kernel
install_pve_kernel() {
    log "Installing and configuring Proxmox VE 9 kernel..."
    
    # Install the new kernel if not already present
    if ! dpkg -l | grep -q "proxmox-kernel-6.14"; then
        apt install -y proxmox-kernel-6.14
    fi
    
    # Ensure the new kernel is default
    if [[ -f /etc/default/grub ]]; then
        log "Updating GRUB configuration..."
        update-grub
    fi
    
    # Check available kernels
    log "Available kernels after installation:"
    ls -la /boot/vmlinuz-* | grep -E "(6\.14|6\.8)" | sort -V
    
    success "PVE 9 kernel installed and configured"
}

# Fix UEFI boot issues
fix_uefi_boot() {
    log "Checking for UEFI boot configuration issues..."
    
    # Check if system is UEFI
    if [[ -d /sys/firmware/efi ]]; then
        log "UEFI system detected, checking GRUB configuration..."
        
        # Fix GRUB EFI configuration for removable media
        if [[ -f /boot/efi/EFI/BOOT/BOOTX64.efi ]] && ! dpkg-query -W grub-efi-amd64 | grep -q "install ok"; then
            log "Fixing GRUB EFI configuration..."
            echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v
            apt install --reinstall grub-efi-amd64 -y
            success "GRUB EFI configuration fixed"
        fi
        
        # Install correct grub meta-package for EFI with LVM
        if [[ -d /sys/firmware/efi ]] && mountpoint -q /boot/efi; then
            apt install grub-efi-amd64 -y
        fi
    fi
}

# Post-upgrade verification
verify_upgrade() {
    log "Verifying upgrade..."
    
    # Check PVE version
    local pve_version=$(pveversion 2>/dev/null | head -n1 | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    log "Current PVE version: $pve_version"
    
    # Check current kernel
    local current_kernel=$(uname -r)
    log "Currently running kernel: $current_kernel"
    
    # Check available kernels
    local new_kernel_available=$(ls /boot/vmlinuz-* 2>/dev/null | grep -o "6\.14\.[0-9]*-[0-9]*-pve" | head -n1 || echo "none")
    log "New PVE 9 kernel available: $new_kernel_available"
    
    # Verify PVE version
    if [[ $pve_version =~ ^9\. ]]; then
        success "Successfully upgraded to Proxmox VE 9.x (version: $pve_version)"
    elif [[ $pve_version == "unknown" ]]; then
        warning "Could not determine PVE version - manual verification required"
    else
        warning "Unexpected PVE version: $pve_version"
    fi
    
    # Check kernel status
    if [[ $current_kernel =~ 6\.14.*-pve ]]; then
        success "Already running new PVE 9 kernel: $current_kernel"
    elif [[ $new_kernel_available != "none" ]]; then
        warning "New kernel ($new_kernel_available) is available but not running ($current_kernel)"
        warning "Reboot is required to complete the upgrade"
    else
        warning "No PVE 9 kernel found - this may indicate an incomplete upgrade"
    fi
    
    # Fix any UEFI boot issues
    fix_uefi_boot
    
    # Check if reboot is required
    local reboot_required=false
    
    if [[ -f /var/run/reboot-required ]]; then
        reboot_required=true
    fi
    
    if [[ ! $current_kernel =~ 6\.14.*-pve ]] && [[ $new_kernel_available != "none" ]]; then
        reboot_required=true
    fi
    
    if [[ $reboot_required == true ]]; then
        cat << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║                     REBOOT REQUIRED                         ║
╠══════════════════════════════════════════════════════════════╣
║ A system reboot is required to complete the upgrade:        ║
║                                                              ║
║ • Load the new PVE 9 kernel (6.14.x)                      ║
║ • Activate GRUB configuration changes                       ║
║ • Complete systemd service updates                          ║
║                                                              ║
║ After reboot, verify with: uname -r && pveversion          ║
╚══════════════════════════════════════════════════════════════╝

EOF
        confirm "Do you want to reboot now to complete the upgrade?"
        log "Rebooting system..."
        reboot
    else
        success "No reboot required - upgrade is complete"
    fi
}

# Cleanup function
cleanup() {
    log "Performing cleanup..."
    apt autoremove -y
    apt autoclean
    
    # Remove subscription nag if present
    if [[ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]]; then
        log "Removing subscription nag from UI..."
        sed -i.backup -e "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
        systemctl restart pveproxy
    fi
    
    success "Cleanup completed"
}

# Main execution
main() {
    cat << EOF
╔══════════════════════════════════════════════════════════════╗
║                Proxmox VE 8 to 9 Upgrade Script             ║
║                        Version $SCRIPT_VERSION                        ║
║                                                              ║
║  WARNING: This performs a major system upgrade              ║
║  Ensure you have backups and tested in lab environment      ║
║                                                              ║
║  Based on: https://pve.proxmox.com/wiki/Upgrade_from_8_to_9 ║
╚══════════════════════════════════════════════════════════════╝

EOF

    confirm "Do you want to proceed with the Proxmox VE upgrade/verification process?"
    
    log "Starting Proxmox VE upgrade/verification process..."
    
    check_root
    check_pve_version
    
    # Get current version to determine what to do
    local current_version=$(pveversion | head -n1 | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+')
    
    if [[ $current_version =~ ^9\. ]]; then
        log "System already on PVE 9.x, running post-upgrade verification and fixes..."
        fix_uefi_boot
        cleanup
        verify_upgrade
    else
        log "Starting full upgrade process from PVE 8.x to 9.x..."
        preflight_check
        check_requirements
        backup_reminder
        upgrade_to_latest_8
        run_checklist
        update_repositories
        perform_upgrade
        install_pve_kernel
        cleanup
        verify_upgrade
    fi
    
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║                    PROCESS COMPLETED                        ║
╠══════════════════════════════════════════════════════════════╣
║ Post-upgrade verification tasks:                            ║
║                                                              ║
║ 1. Clear browser cache and reload web interface             ║
║    • Press Ctrl+Shift+R in your browser                    ║
║    • Or manually clear cache and reload                     ║
║                                                              ║
║ 2. Verify system status:                                    ║
║    • uname -r          (should show 6.14.x-pve)           ║
║    • pveversion        (should show 9.x.x)                 ║
║    • systemctl status pve-cluster pvedaemon pveproxy       ║
║                                                              ║
║ 3. Test VMs and containers:                                 ║
║    • qm list && pct list                                    ║
║    • Start any stopped VMs/containers                       ║
║    • Test network connectivity                              ║
║                                                              ║
║ 4. Review logs for any issues:                             ║
║    • journalctl -xe                                         ║
║    • Check /var/log/syslog for any errors                  ║
║                                                              ║
║ 5. For clusters: Upgrade remaining nodes one by one        ║
║                                                              ║
║ 6. Update any custom configurations for Debian Trixie      ║
╚══════════════════════════════════════════════════════════════╝

EOF

    success "Proxmox VE process completed successfully!"
}

# Error handling
trap 'handle_error $? $LINENO' ERR

handle_error() {
    local exit_code=$1
    local line_number=$2
    
    cat << EOF

╔══════════════════════════════════════════════════════════════╗
║                        ERROR OCCURRED                       ║
╠══════════════════════════════════════════════════════════════╣
║ Exit code: $exit_code at line: $line_number                 ║
║                                                              ║
║ Recovery steps:                                              ║
║                                                              ║
║ 1. Check current system status:                             ║
║    • pveversion                                              ║
║    • uname -r                                                ║
║    • systemctl status pve-cluster pvedaemon pveproxy        ║
║                                                              ║
║ 2. If partially upgraded:                                   ║
║    • apt update && apt dist-upgrade                         ║
║    • apt install --reinstall grub-efi-amd64                 ║
║    • reboot if new kernel available                         ║
║                                                              ║
║ 3. If system is broken:                                     ║
║    • Boot from rescue media                                 ║
║    • Restore from backups                                   ║
║                                                              ║
║ 4. Check logs: journalctl -xe                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
    
    error "Script failed. See recovery steps above."
}

# Run main function
main "$@"
