For some reason the server-setup.sh script pulls a 172 ip address as the gateway IP, which breaks resolution
Limit networking configuration to specific nodes
Convert DNS variables in 50-cloud-init.tpl to read from list instead of string and properly add new IP addresses to DNS entry
server-setup.sh doesn't ignore interactive prompts when running apt-get update, breaking the script