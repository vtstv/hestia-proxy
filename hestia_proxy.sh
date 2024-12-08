#!/bin/bash

# HestiaCP Nginx Template Manager
# https://github.com/vtstv/hestia-proxy
# hestia_proxy v0.2

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
    echo -e "  ${GREEN}fix_ssl${NC}               Reapply / Fix SSL for a domain"
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
    echo "  # Reapply / Fix SSL for a domain"
    echo -e "  ${CYAN}$0 fix-ssl hestiacp_user domain.com${NC}"
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

# Validate domain format
validate_domain_name() {
    local DOMAIN="$1"

    if [[ "$DOMAIN" =~ _ ]]; then
        echo -e "${RED}[ERROR]${NC} Domain names cannot contain underscores (_). (this rule is forced by HestiaCP)"
        return 1
    fi

    if [[ ! "$DOMAIN" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid domain format: $DOMAIN"
        return 1
    fi

    return 0
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

    # Validate domain format
    if ! validate_domain_name "$DOMAIN"; then
        log_message error "Invalid domain format: $DOMAIN"
        return 1
    fi

    if [[ -z "$HESTIA_USER" || -z "$DOMAIN" || -z "$PROXY_TARGET" ]]; then
        log_message error "Usage: $0 add [hestiacp_user] [domain.com] [proxy_target]"
        return 1
    fi

    # Get IP address
    local output=$("$HESTIA/bin/v-list-user-ips" "$HESTIA_USER")
    local nat_ip=$(echo "$output" | awk '$2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $2 }')

    if [[ -z "$nat_ip" ]]; then
        log_message error "Could not retrieve IP for user $HESTIA_USER"
        return 1
    fi

    # Create template
    create_template "$DOMAIN" "$PROXY_TARGET"

    # Add web domain
    if ! "$HESTIA/bin/v-add-web-domain" "$HESTIA_USER" "$DOMAIN" "$nat_ip" "no" "none"; then
        log_message error "Failed to add web domain: $DOMAIN"
        return 1
    fi

    # Add Let's Encrypt SSL
    if ! "$HESTIA/bin/v-add-letsencrypt-domain" "$HESTIA_USER" "$DOMAIN"; then
        log_message error "Failed to add Let's Encrypt SSL for domain: $DOMAIN"
        return 1
    fi

    # Change web domain template
    if ! "$HESTIA/bin/v-change-web-domain-tpl" "$HESTIA_USER" "$DOMAIN" "$DOMAIN"; then
        log_message error "Failed to change web domain template for domain: $DOMAIN"
        return 1
    fi

    log_message info "Domain $DOMAIN setup complete for user $HESTIA_USER"
    return 0
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

    # Search for the primary config and SSL config
    local config_file
    config_file=$(find "$CONFIG_DIR" -name "$DOMAIN.conf" -o -name "$DOMAIN.ssl.conf" | head -n 1)

    if [[ -z "$config_file" ]]; then
        log_message error "No configuration found for $DOMAIN"
        exit 1
    fi

    # Check if nano is available, otherwise fallback to vim
    local editor=${EDITOR:-nano}
    if ! command -v "$editor" &>/dev/null; then
        editor="vim"
    fi

    # Open the configuration file with the selected editor
    "$editor" "$config_file"
}

# List domain configurations
list_configs() {
    log_message info "Domain Configurations:"
    ls "$CONFIG_DIR"
}

# Reapply / Fix SSL for a domain
fix_ssl() {
    local HESTIA_USER="$1"
    local DOMAIN="$2"

    if [[ -z "$HESTIA_USER" || -z "$DOMAIN" ]]; then
        log_message error "Usage: $0 fix-ssl [hestiacp_user] [domain.com]"
        exit 1
    fi

    log_message info "Reapplying SSL for domain: $DOMAIN (User: $HESTIA_USER)"

    "$HESTIA/bin/v-change-web-domain-tpl" "$HESTIA_USER" "$DOMAIN" "default"
    if [[ $? -ne 0 ]]; then
        log_message error "Failed to set template to 'Default' for $DOMAIN"
        exit 1
    fi

    "$HESTIA/bin/v-add-letsencrypt-domain" "$HESTIA_USER" "$DOMAIN"
    if [[ $? -ne 0 ]]; then
        log_message error "Failed to apply Let's Encrypt SSL for $DOMAIN"
        log_message error "Check $HESTIA/logs/LE-* for details."
        exit 1
    fi
    log_message info "Successfully applied Let's Encrypt SSL for $DOMAIN"

    "$HESTIA/bin/v-change-web-domain-tpl" "$HESTIA_USER" "$DOMAIN" "$DOMAIN"
    if [[ $? -ne 0 ]]; then
        log_message error "Failed to reapply custom template for $DOMAIN"
        exit 1
    fi
    log_message info "Successfully reapplied custom template for $DOMAIN"
}

interactive_mode() {
    PS3="$(echo -e ${CYAN}"Select an option: "${NC})"
    options=("Add Proxy Template" "Complete Domain Setup" "List Templates" "Delete Template" "Edit Configuration" "List Configurations" "Fix SSL for a Domain" "Exit")

    echo -e "${CYAN}Welcome to the HestiaCP Nginx Template Management Script${NC}"
    echo -e "${GREEN}Please select an option:${NC}"

    select opt in "${options[@]}"; do
        case $opt in
        "Add Proxy Template")
            echo -e "${YELLOW}Adding a new Proxy Template...${NC}"
            read -p "Enter template name: " template_name
            read -p "Enter proxy target (e.g., http://127.0.0.1:8080): " proxy_target
            PROXY_TARGET="$proxy_target" create_template "$template_name"
            ;;
        "Complete Domain Setup")
            echo -e "${YELLOW}Completing domain setup...${NC}"
            read -p "Enter HestiaCP username: " hestia_user
            while true; do
                read -p "Enter domain name: " domain
                if validate_domain_name "$domain"; then
                    break
                else
                    echo -e "${RED}Invalid domain. Please try again.${NC}"
                fi
            done
            read -p "Enter proxy target: " proxy_target
            complete_domain_setup "$hestia_user" "$domain" "$proxy_target"
            ;;
        "List Templates")
            echo -e "${YELLOW}Listing all templates...${NC}"
            list_templates
            ;;
        "Delete Template")
            echo -e "${YELLOW}Deleting a template...${NC}"
            read -p "Enter template name to delete: " template_name
            delete_template "$template_name"
            ;;
        "Edit Configuration")
            echo -e "${YELLOW}Editing a domain's Nginx configuration...${NC}"
            read -p "Enter domain name: " domain
            edit_nginx_config "$domain"
            ;;
        "List Configurations")
            echo -e "${YELLOW}Listing all domain configurations...${NC}"
            list_configs
            ;;
        "Fix SSL for a Domain")
            echo -e "${YELLOW}Fixing SSL for a domain...${NC}"
            read -p "Enter HestiaCP username: " hestia_user
            while true; do
                read -p "Enter domain name: " domain
                if validate_domain_name "$domain"; then
                    break
                else
                    echo -e "${RED}Invalid domain. Please try again.${NC}"
                fi
            done
            fix_ssl "$hestia_user" "$domain"
            ;;
        "Exit")
            echo -e "${CYAN}Exiting. Have a great day!${NC}"
            break
            ;;
        *)
            echo -e "${RED}Invalid option $REPLY. Please select a valid option.${NC}"
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
    fix-ssl)
        fix_ssl "$2" "$3"
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
