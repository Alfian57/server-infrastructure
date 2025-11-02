#!/bin/bash
# Security Status Check Script
# Displays comprehensive security status

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Header
print_header() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Security Status Report${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# Section header
print_section() {
    echo -e "\n${YELLOW}▶ $1${NC}"
    echo "─────────────────────────────────────────────────────"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# UFW Status
check_ufw() {
    print_section "UFW Firewall Status"
    
    if command_exists ufw; then
        if ufw status | grep -q "Status: active"; then
            echo -e "${GREEN}✓${NC} UFW is active"
            echo ""
            ufw status verbose
        else
            echo -e "${RED}✗${NC} UFW is not active"
        fi
    else
        echo -e "${RED}✗${NC} UFW is not installed"
    fi
}

# Fail2ban Status
check_fail2ban() {
    print_section "Fail2ban Status"
    
    if command_exists fail2ban-client; then
        if systemctl is-active --quiet fail2ban; then
            echo -e "${GREEN}✓${NC} Fail2ban is running"
            echo ""
            fail2ban-client status
            
            echo ""
            echo "Active jails:"
            for jail in $(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g'); do
                echo ""
                echo "  Jail: $jail"
                fail2ban-client status "$jail" | grep -E "Currently banned:|Total banned:"
            done
        else
            echo -e "${RED}✗${NC} Fail2ban is not running"
        fi
    else
        echo -e "${RED}✗${NC} Fail2ban is not installed"
    fi
}

# SSH Configuration
check_ssh() {
    print_section "SSH Security Configuration"
    
    if [ -f /etc/ssh/sshd_config ]; then
        echo "Key settings:"
        echo ""
        
        # Root login
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
        if [ "$root_login" == "no" ]; then
            echo -e "  ${GREEN}✓${NC} Root login: disabled"
        else
            echo -e "  ${YELLOW}⚠${NC} Root login: $root_login"
        fi
        
        # Password auth
        pass_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}')
        if [ "$pass_auth" == "no" ]; then
            echo -e "  ${GREEN}✓${NC} Password authentication: disabled"
        else
            echo -e "  ${YELLOW}⚠${NC} Password authentication: $pass_auth"
        fi
        
        # Max auth tries
        max_tries=$(grep "^MaxAuthTries" /etc/ssh/sshd_config | awk '{print $2}')
        echo -e "  ${GREEN}✓${NC} Max auth tries: ${max_tries:-6}"
        
        # Port
        ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
        echo -e "  ${GREEN}✓${NC} SSH port: ${ssh_port:-22}"
    else
        echo -e "${RED}✗${NC} SSH config not found"
    fi
}

# Docker Security
check_docker() {
    print_section "Docker Security"
    
    if command_exists docker; then
        echo "Docker daemon configuration:"
        echo ""
        
        # Check userns-remap
        if docker info 2>/dev/null | grep -q "userns"; then
            echo -e "  ${GREEN}✓${NC} User namespace remapping: enabled"
        else
            echo -e "  ${YELLOW}⚠${NC} User namespace remapping: disabled"
        fi
        
        # Check seccomp
        if [ -f /etc/docker/seccomp/default.json ]; then
            echo -e "  ${GREEN}✓${NC} Seccomp profile: present"
        else
            echo -e "  ${YELLOW}⚠${NC} Seccomp profile: not found"
        fi
        
        # Check AppArmor
        if [ -f /etc/apparmor.d/docker-default ]; then
            echo -e "  ${GREEN}✓${NC} AppArmor profile: present"
        else
            echo -e "  ${YELLOW}⚠${NC} AppArmor profile: not found"
        fi
        
        # Running containers
        container_count=$(docker ps -q | wc -l)
        echo ""
        echo "  Running containers: $container_count"
    else
        echo -e "${RED}✗${NC} Docker is not installed"
    fi
}

# System Security
check_system() {
    print_section "System Security"
    
    echo "Kernel parameters:"
    echo ""
    
    # SYN cookies
    syn_cookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
    if [ "$syn_cookies" == "1" ]; then
        echo -e "  ${GREEN}✓${NC} SYN flood protection: enabled"
    else
        echo -e "  ${RED}✗${NC} SYN flood protection: disabled"
    fi
    
    # IP forwarding
    ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    if [ "$ip_forward" == "0" ]; then
        echo -e "  ${GREEN}✓${NC} IP forwarding: disabled"
    else
        echo -e "  ${YELLOW}⚠${NC} IP forwarding: enabled"
    fi
    
    # Reverse path filtering
    rp_filter=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null)
    if [ "$rp_filter" == "1" ]; then
        echo -e "  ${GREEN}✓${NC} Reverse path filtering: enabled"
    else
        echo -e "  ${RED}✗${NC} Reverse path filtering: disabled"
    fi
    
    # Auto updates
    echo ""
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
        echo -e "  ${GREEN}✓${NC} Automatic security updates: configured"
    else
        echo -e "  ${YELLOW}⚠${NC} Automatic security updates: not configured"
    fi
}

# Recent Security Events
check_recent_events() {
    print_section "Recent Security Events (Last 24 Hours)"
    
    echo "Failed SSH attempts:"
    if [ -f /var/log/auth.log ]; then
        failed_ssh=$(grep "Failed password" /var/log/auth.log | grep "$(date +%b\ %_d)" | wc -l)
        if [ "$failed_ssh" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠${NC} $failed_ssh failed SSH login attempts today"
        else
            echo -e "  ${GREEN}✓${NC} No failed SSH attempts today"
        fi
    fi
    
    echo ""
    echo "UFW blocks:"
    if [ -f /var/log/ufw.log ]; then
        ufw_blocks=$(grep "BLOCK" /var/log/ufw.log | grep "$(date +%b\ %_d)" | wc -l)
        if [ "$ufw_blocks" -gt 0 ]; then
            echo -e "  ${BLUE}ℹ${NC} $ufw_blocks connection(s) blocked by UFW today"
        else
            echo -e "  ${GREEN}✓${NC} No blocks by UFW today"
        fi
    fi
    
    echo ""
    echo "Fail2ban bans:"
    if [ -f /var/log/fail2ban.log ]; then
        bans_today=$(grep "Ban" /var/log/fail2ban.log | grep "$(date +%Y-%m-%d)" | wc -l)
        if [ "$bans_today" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠${NC} $bans_today IP(s) banned by Fail2ban today"
        else
            echo -e "  ${GREEN}✓${NC} No bans by Fail2ban today"
        fi
    fi
}

# Open Ports
check_open_ports() {
    print_section "Open Ports"
    
    if command_exists ss; then
        echo "Listening TCP ports:"
        ss -tlnp | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -n | uniq | while read -r port; do
            echo "  • Port $port"
        done
    elif command_exists netstat; then
        echo "Listening TCP ports:"
        netstat -tlnp | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -n | uniq | while read -r port; do
            echo "  • Port $port"
        done
    else
        echo -e "${YELLOW}⚠${NC} No tool available to check open ports"
    fi
}

# Summary
print_summary() {
    print_section "Summary"
    
    security_score=0
    total_checks=6
    
    # UFW
    if command_exists ufw && ufw status | grep -q "Status: active"; then
        ((security_score++))
        echo -e "${GREEN}✓${NC} Firewall: Active"
    else
        echo -e "${RED}✗${NC} Firewall: Inactive"
    fi
    
    # Fail2ban
    if command_exists fail2ban-client && systemctl is-active --quiet fail2ban; then
        ((security_score++))
        echo -e "${GREEN}✓${NC} Intrusion Prevention: Active"
    else
        echo -e "${RED}✗${NC} Intrusion Prevention: Inactive"
    fi
    
    # SSH
    if [ -f /etc/ssh/sshd_config ]; then
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
        pass_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}')
        if [ "$root_login" == "no" ] && [ "$pass_auth" == "no" ]; then
            ((security_score++))
            echo -e "${GREEN}✓${NC} SSH: Hardened"
        else
            echo -e "${YELLOW}⚠${NC} SSH: Partially hardened"
        fi
    else
        echo -e "${RED}✗${NC} SSH: Not configured"
    fi
    
    # Docker
    if command_exists docker; then
        ((security_score++))
        echo -e "${GREEN}✓${NC} Docker: Installed"
    else
        echo -e "${YELLOW}⚠${NC} Docker: Not installed"
    fi
    
    # System
    syn_cookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
    if [ "$syn_cookies" == "1" ]; then
        ((security_score++))
        echo -e "${GREEN}✓${NC} System: Hardened"
    else
        echo -e "${YELLOW}⚠${NC} System: Not fully hardened"
    fi
    
    # Auto updates
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
        ((security_score++))
        echo -e "${GREEN}✓${NC} Auto-updates: Enabled"
    else
        echo -e "${YELLOW}⚠${NC} Auto-updates: Disabled"
    fi
    
    echo ""
    echo -e "Security Score: ${CYAN}$security_score/$total_checks${NC}"
    
    percentage=$((security_score * 100 / total_checks))
    if [ "$percentage" -ge 80 ]; then
        echo -e "Status: ${GREEN}Excellent${NC}"
    elif [ "$percentage" -ge 60 ]; then
        echo -e "Status: ${YELLOW}Good${NC}"
    else
        echo -e "Status: ${RED}Needs Improvement${NC}"
    fi
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠ Warning: Some checks require root privileges${NC}"
        echo "Run with: sudo $0"
        echo ""
    fi
    
    print_header
    check_ufw
    check_fail2ban
    check_ssh
    check_docker
    check_system
    check_recent_events
    check_open_ports
    print_summary
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# Run
main "$@"
