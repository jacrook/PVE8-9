# PVE8-9
# Proxmox VE Upgrade Scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Proxmox VE](https://img.shields.io/badge/Proxmox-VE-E57000?logo=proxmox&logoColor=white)](https://www.proxmox.com/en/proxmox-ve)

Automated scripts for upgrading Proxmox Virtual Environment between major versions with comprehensive safety checks and error handling.

## ⚠️ **CRITICAL DISCLAIMERS - READ BEFORE USE**

### 🚨 USE AT YOUR OWN RISK 🚨

**THIS SCRIPT PERFORMS MAJOR SYSTEM MODIFICATIONS THAT CAN RENDER YOUR SYSTEM UNBOOTABLE OR CAUSE DATA LOSS.**

- **NOT RESPONSIBLE FOR ANY DATA LOSS, SYSTEM DAMAGE, OR DOWNTIME**
- **NO WARRANTY PROVIDED - USE ENTIRELY AT YOUR OWN RISK**
- **ALWAYS TEST IN DEVELOPMENT ENVIRONMENT FIRST**
- **NEVER RUN ON PRODUCTION WITHOUT EXTENSIVE TESTING**
- **ENSURE COMPLETE BACKUPS BEFORE PROCEEDING**

### 🧪 **MANDATORY TESTING REQUIREMENTS**

Before using this script on ANY production system:

1. **Set up an identical test environment**
2. **Run the script on test systems multiple times**
3. **Verify all your VMs and containers work post-upgrade**
4. **Document any issues and solutions**
5. **Only then consider using on production with proper maintenance windows**

## 📋 Overview

This repository contains automated upgrade scripts for Proxmox Virtual Environment (PVE) that help transition between major versions while maintaining system integrity and minimizing downtime.

### Current Scripts

- **`proxmox-8to9-upgrade.sh`** - Upgrades Proxmox VE 8.x to 9.x (Debian Bookworm → Trixie)

## ✨ Features

- 🔍 **Pre-flight System Checks** - Network, disk space, dependencies
- 🛡️ **Safety Mechanisms** - Multiple confirmation prompts and backup reminders
- 📝 **Comprehensive Logging** - Detailed progress tracking and error reporting
- 🔧 **Automatic Repository Management** - Handles Debian and Proxmox repository transitions
- 💾 **Configuration Backup** - Automatic backup of critical configurations
- 🖥️ **UEFI/BIOS Support** - Handles both boot methods and fixes common issues
- 🔄 **Kernel Management** - Ensures proper kernel installation and boot configuration
- ✅ **Post-Upgrade Verification** - Validates successful upgrade completion
- 📱 **Cluster Awareness** - Detects and provides guidance for cluster environments
- 🚨 **Error Recovery** - Comprehensive error handling with recovery guidance

## 🛠️ Prerequisites

### System Requirements

- Proxmox VE 8.x installation (8.4.x recommended)
- Root access to the system
- Stable internet connection
- At least 5GB free disk space
- Console access (IPMI/iLO recommended for production)

### Essential Pre-Upgrade Steps

1. **Complete System Backup**
   ```bash
   # Backup all VMs and containers
   vzdump --all --storage <backup-storage> --mode snapshot
   
   # Backup configuration
   tar -czf /tmp/pve-config-backup.tar.gz /etc/pve/ /etc/network/interfaces /etc/hosts
   ```

2. **Update to Latest PVE 8.4.x**
   ```bash
   apt update && apt dist-upgrade
   pveversion  # Should show 8.4.x
   ```

3. **Ceph Users** (if applicable)
   ```bash
   # Upgrade Ceph to Squid before PVE upgrade
   # Follow: https://pve.proxmox.com/wiki/Ceph_Reef_to_Squid
   ```

## 📦 Installation

### Method 1: Direct Download (Recommended)

```bash
# Download the script
wget https://raw.githubusercontent.com/YOUR-USERNAME/proxmox-upgrade-scripts/main/scripts/proxmox-8to9-upgrade.sh

# Make executable
chmod +x proxmox-8to9-upgrade.sh

# Verify download integrity (optional but recommended)
sha256sum proxmox-8to9-upgrade.sh
```

### Method 2: Clone Repository

```bash
git clone https://github.com/YOUR-USERNAME/proxmox-upgrade-scripts.git
cd proxmox-upgrade-scripts/scripts
chmod +x proxmox-8to9-upgrade.sh
```

## 🚀 Usage

### For Testing Environments

```bash
# Run directly for testing
./proxmox-8to9-upgrade.sh
```

### For Production Environments

**ALWAYS use tmux or screen to prevent SSH disconnection issues:**

```bash
# Start tmux session
tmux new-session -d -s pve-upgrade

# Attach to session
tmux attach-session -t pve-upgrade

# Run the upgrade script
./proxmox-8to9-upgrade.sh

# If disconnected, reconnect with:
# tmux attach-session -t pve-upgrade
```

### Cluster Environments

**Upgrade nodes ONE AT A TIME:**

```bash
# Node 1: Run upgrade, wait for completion and verification
./proxmox-8to9-upgrade.sh

# Wait for node to be fully operational
# Verify cluster status: pvecm status

# Only then proceed to Node 2, then Node 3, etc.
```

## 🔧 Post-Upgrade Verification

After the script completes, verify your system:

```bash
# Check versions
uname -r          # Should show 6.14.x-pve kernel
pveversion        # Should show 9.x.x

# Check services
systemctl status pve-cluster pvedaemon pveproxy

# Clear browser cache and test web interface
# Press Ctrl+Shift+R in browser

# Test VMs and containers
qm list           # List VMs
pct list          # List containers

# Start any stopped VMs/containers
qm start <vmid>
pct start <ctid>

# Check logs for issues
journalctl -xe
```

## 🔍 Troubleshooting

### Common Issues

#### GRUB/Boot Issues
```bash
# Fix UEFI boot problems
echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v
apt install --reinstall grub-efi-amd64
```

#### Kernel Not Loading
```bash
# Check available kernels
ls /boot/vmlinuz-*

# Ensure GRUB is updated
update-grub

# Reboot if new kernel available
reboot
```

#### Service Issues
```bash
# Restart PVE services
systemctl restart pve-cluster pvedaemon pveproxy

# Check cluster status (if applicable)
pvecm status
```

#### Package Conflicts
```bash
# Fix broken packages
apt --fix-broken install

# Complete interrupted upgrade
apt dist-upgrade
```

### Recovery Procedures

If the upgrade fails:

1. **Check current status:**
   ```bash
   pveversion
   systemctl status pve-cluster pvedaemon pveproxy
   ```

2. **Attempt to complete upgrade:**
   ```bash
   apt update
   apt dist-upgrade
   ```

3. **If system is broken:**
   - Boot from rescue media
   - Restore from backups
   - Contact Proxmox support if you have a subscription

## 📚 Additional Resources

- [Official Proxmox VE 8 to 9 Upgrade Guide](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Community Forum](https://forum.proxmox.com/)
- [Debian Trixie Release Notes](https://www.debian.org/releases/trixie/)

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Test thoroughly** in lab environments
2. **Document changes** clearly
3. **Follow bash best practices**
4. **Include error handling**
5. **Update documentation** as needed

### Development Workflow

```bash
# Fork the repository
# Create feature branch
git checkout -b feature/improvement-name

# Make changes and test extensively
# Commit with clear messages
git commit -m "feat: add improved error handling for X"

# Push and create pull request
git push origin feature/improvement-name
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Final Warnings

### Before Using This Script

- [ ] I have read and understood all disclaimers
- [ ] I have complete, tested backups of all data
- [ ] I have tested this script in a development environment
- [ ] I have a maintenance window scheduled
- [ ] I have console access to the server
- [ ] I understand the risks of major system upgrades
- [ ] I accept full responsibility for any consequences

### Emergency Contacts

- **Proxmox Support:** (If you have a subscription)
- **Your System Administrator**
- **Your Backup/Disaster Recovery Team**

---

## 🙏 Acknowledgments

- Based on official Proxmox VE upgrade documentation
- Inspired by community feedback and real-world usage
- Special thanks to the Proxmox development team

---

**Remember: When in doubt, don't upgrade. A working Proxmox VE 8.x system is better than a broken Proxmox VE 9.x system.**

## 📊 Version Compatibility Matrix

| Script Version | Proxmox VE Source | Proxmox VE Target | Debian Source | Debian Target | Status |
|----------------|-------------------|-------------------|---------------|---------------|---------|
| 1.0.0          | 8.4.x            | 9.0.x            | Bookworm      | Trixie        | ✅ Stable |

---

*Last updated: $(date +'%Y-%m-%d')*
