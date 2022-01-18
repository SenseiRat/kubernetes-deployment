#!/bin/bash

# Handle inputs
while getopts ":a:h:i:m:k:" opt
do
	case "${opt}" in
		a ) TARGET_IP=${OPTARG};;
		h ) HOST_NAME=${OPTARG};;
		i ) CURRENT_IP=${OPTARG};;
		m ) MAINT_USER=${OPTARG};;
		* ) display_help;;
	esac
done

if [[ $OPTIND -eq 1 ]] || [[ -z $TARGET_IP ]] || \
   [[ -z $CURRENT_IP ]] || [[ -z $HOST_NAME ]]; then
	echo -e "\nUsage: ./server-setup.sh -[a|d|H|i|m|u|h]"
	echo -e "\t-a: Target IP address (what you want the node to be assigned)"
	echo -e "\t-h: Hostname"
	echo -e "\t-i: Current IP (dhcp assigned IP when node first spins up)"
	echo -e "\t-m: Maintenance user name"
	exit 1
fi

# Set some defaults
SSH_OPTS="StrictHostKeyChecking=no"
DEFAULT_USER="ubuntu"
DEFAULT_PASS="ubuntu"
TEMP_PASS="TempPass123"
DEFAULT_SUDOERS="/etc/sudoers.d/90-cloud-init-users"
MAINT_USER="ansible"
MAINT_PUB_KEY=$(cat "/home/sean/.ssh/${MAINT_USER}_id_rsa.pub")
IP_REGEX="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
# GATEWAY_IP=$(ip r | grep default | grep -Eo "${IP_REGEX}" | head -n1)
GATEWAY_IP="192.168.1.1"
NET_CFG=$(sed -e "s/{{TARGET_IP}}/${TARGET_IP}/" -e "s/{{GATEWAY_IP}}/$GATEWAY_IP/" ../templates/50-cloud-init.yaml)

# Perform some checks on the control machine
if ! which sshpass; then
	echo "Install sshpass before running this script."
	exit 1
elif ! which expect; then
	echo "Install expect before running this script."
	exit 1
fi

# Set a temporary password because Ubuntu will force the change
/usr/bin/expect << EOF
	#!/usr/bin/expect -f
	spawn ssh -o ${SSH_OPTS} ${DEFAULT_USER}@${CURRENT_IP}
	expect -re {password: $}
	sleep 1
	send "${DEFAULT_PASS}\r"
	expect -re {password: $}
	sleep 1
	send "${DEFAULT_PASS}\r"
	expect -re {password: $}
	sleep 1
	send "${TEMP_PASS}\r"
	expect -re {password: $}
	sleep 1
	send "${TEMP_PASS}\r"
	expect
EOF

# Create the maintenance account, update the sudoers files, and configure the host
sshpass -p ${TEMP_PASS} ssh -tt -o ${SSH_OPTS} "${DEFAULT_USER}@${CURRENT_IP}" << EOF
    echo "Password reset successfully."
	# Add maintenance account
	echo ${TEMP_PASS} | sudo -S echo "Adding Ansible maintenance account"
	sudo useradd -d /home/${MAINT_USER} -m -s /bin/bash -r ${MAINT_USER}
	sudo mkdir -p /home/${MAINT_USER}/.ssh
	echo "${MAINT_PUB_KEY}" >> authorized_keys
	sudo mv authorized_keys /home/${MAINT_USER}/.ssh/authorized_keys 
	sudo chown -R ${MAINT_USER}:${MAINT_USER} /home/${MAINT_USER}/.ssh

	# Update sudoers files
	echo ${TEMP_PASS} | sudo -S echo "Setting sudoers permissions"
	sudo echo -e "# User rules for ${MAINT_USER} service account\n${MAINT_USER} ALL=(ALL) NOPASSWD:ALL" > 90-${MAINT_USER}-permissions
	sudo chown 0:0 90-${MAINT_USER}-permissions
	sudo chmod 440 90-${MAINT_USER}-permissions
	sudo mv 90-${MAINT_USER}-permissions /etc/sudoers.d/90-${MAINT_USER}-permissions
	sudo mv ${DEFAULT_SUDOERS} ${DEFAULT_SUDOERS}~

	# Set hostname and static IP, install updates, and reboot
	echo ${TEMP_PASS} | sudo -S echo "Setting hostname, static IP, and installing updates"
	sudo hostnamectl set-hostname ${HOST_NAME}
	echo 'network: {config: disabled}' | sudo dd of=/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
	echo "${NET_CFG}" | sudo dd of=/etc/netplan/50-cloud-init.yaml
	sudo apt-get update -yq && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq
	echo "Rebooting, please stand by..."
	sudo reboot
EOF

# Sleep while we wait for the system to come back up
sleep 5 # this is to make sure we don't ping before the system has gone down
while :; do
	if sudo ping -c 1 "${CURRENT_IP}" | grep '64 bytes from'; then
		break
	fi
	echo "..."
	sleep 5
done

# Run Kubernetes Playbook
echo "Initiating Ansible playbook..."
sleep 5
#ansible-playbook -i ../hosts.yml ../master-playbook.yml -v
