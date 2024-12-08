#!/bin/bash

# HestiaCP Nginx Template Manager
# https://github.com/vtstv/hestia-proxy

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run as root. Use 'sudo' to execute it."
    exit 1
fi

HESTIA=${HESTIA:-/usr/local/hestia}

TEMPLATE_DIR="$HESTIA/data/templates/web/nginx/php-fpm"
CONFIG_DIR="/etc/nginx/conf.d/domains"
BACKUP_DIR="$HESTIA/data/templates/web/nginx_backup"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

display_help() {
    echo -e "${CYAN}HestiaCP Nginx Template Management Script${NC}"
    echo "Manages Nginx templates and domain configurations in HestiaCP"
    echo
    echo -e "${GREEN}Usage:${NC}"
    echo "  $0 [COMMAND] [OPTIONS]"
    echo
    echo -e "${YELLOW}Commands:${NC}"
    echo -e "  ${GREEN}list${NC}                  List available Nginx templates"
    echo -e "  ${GREEN}add${NC}                   Add a new template or complete domain setup"
    echo -e "  ${GREEN}delete${NC}                Delete an existing template"
    echo -e "  ${GREEN}edit${NC}                  Edit domain Nginx configuration"
    echo -e "  ${GREEN}configs${NC}               List domain configurations"
    echo -e "  ${GREEN}--help${NC}, ${GREEN}-h${NC}            Show this help message"
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  # List all available templates"
    echo -e "  ${CYAN}$0 list${NC}"
    echo
    echo "  # Add a new Nginx proxy template"
    echo -e "  ${CYAN}$0 add example_template http://127.0.0.1:8080${NC}"
    echo
    echo "  # Complete domain setup with proxy"
    echo -e "  ${CYAN}$0 add hestiacp_user domain.com http://127.0.0.1:8080${NC}"
    echo
    echo "  # Delete an existing template"
    echo -e "  ${CYAN}$0 delete example_template${NC}"
    echo
    echo "  # Edit a domain's Nginx configuration"
    echo -e "  ${CYAN}$0 edit domain.com${NC}"
    echo
    echo -e "${RED}Note:${NC} This script must be run with root privileges"
    echo
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "- Ensure HestiaCP is installed"
    echo "- Verify correct paths and user permissions"
    echo "- Check HestiaCP logs for detailed error information"
}

# Logging function
log_message() {
    local type="$1"
    local message="$2"
    case "$type" in
    info)
        echo -e "${GREEN}[INFO]${NC} $message"
        ;;
    error)
        echo -e "${RED}[ERROR]${NC} $message" >&2
        ;;
    warning)
        echo -e "${YELLOW}[WARNING]${NC} $message"
        ;;
    *)
        echo "$message"
        ;;
    esac
}

# Validate proxy target
validate_proxy_target() {
    if [[ -z "$PROXY_TARGET" ]]; then
        log_message error "Proxy target is required."
        exit 1
    fi

    # Basic URL validation
    if [[ ! "$PROXY_TARGET" =~ ^https?:// ]]; then
        log_message error "Invalid proxy target. Must start with http:// or https://"
        exit 1
    fi
}

# Create Nginx template files
create_template() {
    local DOMAIN_NAME="${1:-default_template}"
    local PROXY_TARGET="${2:-http://127.0.0.1:8080}"

    mkdir -p "$TEMPLATE_DIR"

    cat <<EOF >"$TEMPLATE_DIR/$DOMAIN_NAME.tpl"
server {
    listen      %ip%:%web_port%;
    server_name %domain_idn% %alias_idn%;
    location / {
        proxy_pass $PROXY_TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    cat <<EOF >"$TEMPLATE_DIR/$DOMAIN_NAME.stpl"
server {
    listen      %ip%:%web_ssl_port% ssl http2;
    server_name %domain_idn% %alias_idn%;
    ssl_certificate      %ssl_pem%;
    ssl_certificate_key  %ssl_key%;
    location / {
        proxy_pass $PROXY_TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    log_message info "Created Nginx templates for $DOMAIN_NAME"
}

complete_domain_setup() {
    local HESTIA_USER="$1"
    local DOMAIN="$2"
    local PROXY_TARGET="$3"

    if [[ -z "$HESTIA_USER" || -z "$DOMAIN" || -z "$PROXY_TARGET" ]]; then
        log_message error "Usage: $0 add [hestiacp_user] [domain.com] [proxy_target]"
        exit 1
    fi

    # Get IP address
    local output=$("$HESTIA/bin/v-list-user-ips" "$HESTIA_USER")
    local nat_ip=$(echo "$output" | awk '$2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $2 }')

    if [[ -z "$nat_ip" ]]; then
        log_message error "Could not retrieve IP for user $HESTIA_USER"
        exit 1
    fi

    create_template "$DOMAIN" "$PROXY_TARGET"

    "$HESTIA/bin/v-add-web-domain" "$HESTIA_USER" "$DOMAIN" "$nat_ip" "no" "none"

    "$HESTIA/bin/v-add-letsencrypt-domain" "$HESTIA_USER" "$DOMAIN"

    "$HESTIA/bin/v-change-web-domain-tpl" "$HESTIA_USER" "$DOMAIN" "$DOMAIN"

    log_message info "Domain $DOMAIN setup complete for user $HESTIA_USER"
}

# List available templates
list_templates() {
    log_message info "Available Nginx Templates:"
    ls "$TEMPLATE_DIR"/*.tpl 2>/dev/null | sed 's/.*\///; s/\.tpl$//'
}

# Delete a template
delete_template() {
    local TEMPLATE_NAME="$1"

    if [[ -z "$TEMPLATE_NAME" ]]; then
        log_message error "Please specify a template name to delete"
        exit 1
    fi

    mkdir -p "$BACKUP_DIR"

    # Backup before deleting
    cp "$TEMPLATE_DIR/$TEMPLATE_NAME.tpl" "$BACKUP_DIR/$TEMPLATE_NAME.tpl.bak" 2>/dev/null
    cp "$TEMPLATE_DIR/$TEMPLATE_NAME.stpl" "$BACKUP_DIR/$TEMPLATE_NAME.stpl.bak" 2>/dev/null

    # Remove template files
    rm "$TEMPLATE_DIR/$TEMPLATE_NAME.tpl" 2>/dev/null
    rm "$TEMPLATE_DIR/$TEMPLATE_NAME.stpl" 2>/dev/null

    log_message info "Deleted template $TEMPLATE_NAME (backed up in $BACKUP_DIR)"
}

edit_nginx_config() {
    local DOMAIN="$1"

    if [[ -z "$DOMAIN" ]]; then
        log_message error "Please specify a domain to edit"
        exit 1
    fi

    # Find the configuration file
    local config_file
    config_file=$(find "$CONFIG_DIR" -name "*$DOMAIN*.conf")

    if [[ -z "$config_file" ]]; then
        log_message error "No configuration found for $DOMAIN"
        exit 1
    fi

    # Open the configuration file with the default editor
    ${EDITOR:-nano} "$config_file"
}

# List domain configurations
list_configs() {
    log_message info "Domain Configurations:"
    ls "$CONFIG_DIR"
}

interactive_mode() {
    PS3="Select an option: "
    options=("Add only Proxy Template" "Complete Domain Setup" "List Templates" "Delete Template" "Edit Configuration" "List Configurations" "Exit")

    select opt in "${options[@]}"; do
        case $opt in
        "Add Proxy only Template")
            read -p "Enter template name: " template_name
            read -p "Enter proxy target (e.g., http://127.0.0.1:8080): " proxy_target
            PROXY_TARGET="$proxy_target" create_template "$template_name"
            ;;
        "Complete Domain Setup")
            read -p "Enter HestiaCP username: " hestia_user
            read -p "Enter domain name: " domain
            read -p "Enter proxy target: " proxy_target
            complete_domain_setup "$hestia_user" "$domain" "$proxy_target"
            ;;
        "List Templates")
            list_templates
            ;;
        "Delete Template")
            read -p "Enter template name to delete: " template_name
            delete_template "$template_name"
            ;;
        "Edit Configuration")
            read -p "Enter domain name: " domain
            edit_nginx_config "$domain"
            ;;
        "List Configurations")
            list_configs
            ;;
        "Exit")
            break
            ;;
        *)
            echo "Invalid option $REPLY"
            ;;
        esac
    done
}

main() {

    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        display_help
        exit 0
    fi

    if [[ $EUID -ne 0 ]]; then
        log_message error "This script must be run as root"
        exit 1
    fi

    case "$1" in
    list)
        list_templates
        ;;
    add)
        if [[ $# -eq 4 ]]; then
            complete_domain_setup "$2" "$3" "$4"
        elif [[ $# -eq 3 ]]; then
            PROXY_TARGET="$3" create_template "$2"
        else
            interactive_mode
        fi
        ;;
    delete)
        delete_template "$2"
        ;;
    edit)
        edit_nginx_config "$2"
        ;;
    configs)
        list_configs
        ;;
    *)
        if [[ $# -eq 0 ]]; then
            interactive_mode
        else
            display_help
            exit 1
        fi
        ;;
    esac
}

main "$@"
