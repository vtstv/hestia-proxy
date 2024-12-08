# HestiaCP Nginx Template Manager

A Bash script designed to simplify the management of Nginx templates and reverse proxy configurations for **HestiaCP**. 
This tool enables you to create, edit, delete, and manage domain configurations with ease.

---

## Features

-  **Template Management**: Add, delete, and list Nginx templates effortlessly.
-  **Domain Configuration**: Quickly set up complete reverse proxy configurations for domains, including SSL support.
-  **Interactive Mode**: User-friendly prompts for managing templates and domains.
-  **Backup Functionality**: Automatically backs up templates before deletion to avoid data loss.
-  **Edit Configurations**: Easily open and modify Nginx domain configuration files.

---

## Requirements

- **HestiaCP**: Installed and configured on the server.
- **Root Access**: This script requires root privileges to execute.
- **Nginx**: The script manages templates for Nginx as the web server.

---

## Installation

Clone this repository to your server:
   
   git clone https://github.com/vtstv/hestia-proxy.git
   cd hestia-proxy
   chmod +x ./hestia_proxy.sh
or 

```
git clone https://github.com/vtstv/hestia-proxy.git && cd hestia-proxy && chmod +x ./hestia_proxy.sh
```

## Modes of Operation

This script supports two modes of operation:

**Interactive Mode:**

Run the script without arguments to enter an interactive menu for managing templates and domains.
Example:
```
sudo ./hestia_proxy.sh
```
or

**CLI Mode:**

Run the script with arguments for direct execution of specific tasks.

Examples:

Full Domain Setup for a User
```
sudo ./hestia_proxy.sh add hestia_user mywebsite.com http://192.168.1.100:5000
```
This sets up a domain (mywebsite.com) for the user hestia_user with a reverse proxy to http://192.168.1.100:5000, including SSL configuration.

Adding a Reverse Proxy Template
```
sudo ./hestia_proxy.sh add domain.com http://127.0.0.1:3000
```
This command creates a new reverse proxy template named domain.com pointing to a backend service running on http://127.0.0.1:3000.

Deleting an Existing Template
```
sudo ./hestia_proxy.sh delete domain.com
```
Deletes the reverse_proxy_template and backs it up in the nginx_backup directory.



**Notes**

Backup Your Data: Always back up your templates and configurations before making changes.
Ensure HestiaCP Installation: This script assumes HestiaCP is installed and operational.
Permissions: Run the script as the root user or with sudo for proper access.

**Compatibility**

⚠️ This is an early version of the script, tested on Ubuntu 22.04 LTS with HestiaCP 1.8.12.
Use it with caution and ensure you test it in a development environment before applying it to production servers.

License

This project is licensed under the MIT License.

I hope a native solution for reverse proxy will be added to HestiaCP, so we won't have to rely on such methods...