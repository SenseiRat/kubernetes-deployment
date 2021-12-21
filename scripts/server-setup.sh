#!/bin/bash
# TODO: This whole script has become overly complex and needs a major rework

function display_help {
	echo -e "\nUsage: ./server-setup.sh -[a|d|H|i|m|u|h]"
	echo -e "\t-a: Target IP address (what you want the node to be assigned)"
	echo -e "\t-h: Hostname"
	echo -e "\t-i: Current IP (dhcp assigned IP when node first spins up)"
	echo -e "\t-m: Maintenance user name"
	echo -e "\t-u: Admin user name"
	exit 1
}

# Handle inputs
while getopts ":a:d:h:i:m:u:" opt
do
	case "${opt}" in
		a ) TARGET_IP=${OPTARG};;
		h ) HOST_NAME=${OPTARG};;
		i ) CURRENT_IP=${OPTARG};;
		m ) MAINT_USER=${OPTARG};;
		u ) ADMIN_USER=${OPTARG};;
		* ) display_help;;
	esac
done

# Check user inputs and set defaults if not passed
if [[ $OPTIND -eq 1 ]]; then
	display_help
fi
if [[ -z $TARGET_IP ]]; then
	# Attempt to determine the desired IP from the ansible configuration file
	if ! TARGET_IP=$(grep -A1 "{$HOST_NAME}" ../hosts.yml | grep -Eo "${IP_REGEX}"); then
		echo "No target IP address defined and unable to determine automatically."
		exit 1
	fi
fi
if [[ -z $ADMIN_USER ]]; then
	ADMIN_USER="sean"
	echo "Using default of sean for admin user name."
fi
if [[ -z $DISTRO ]]; then
	DISTRO="ubuntu"
	echo "Using default of ubuntu for distribution."
fi
if [[ -z $HOST_NAME ]]; then
	echo "Please set hostname with -h switch."
	exit 1
fi
if [[ -z $CURRENT_IP ]]; then
	echo "Please specify the DHCP IP address for the target device."
	exit 1
fi
if [[ -z $MAINT_USER ]]; then
	MAINT_USER="ansible"
	echo "Using default of ansible for maintenance user."
fi

# Set some defaults
SSH_OPTS="StrictHostKeyChecking=no"
DEFAULT_USER="ubuntu"
DEFAULT_PASS="TempPass123" #"ubuntu"
TEMP_PASS="TempPass123"
GROUP_LIST="sudo,adm,dialout,cdrom,floppy,audio,dip,video,plugdev,netdev,lxd"
DEFAULT_SUDOERS="/etc/sudoers.d/90-cloud-init-users"

IP_REGEX="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
GATEWAY_IP=$(ip r | grep default | grep -Eo "${IP_REGEX}" | head -n1)
NET_CFG=$(sed "s/{{TARGET_IP}}/${TARGET_IP}/; s/{{GATEWAY_IP}}/$GATEWAY_IP}/"../templates/50-cloud-init.yaml)

# Set up to automatically pull the public SSH keys
ADMIN_PUB_KEY=$(cat "/home/${ADMIN_USER}/.ssh/id_rsa.pub")
MAINT_PUB_KEY=$(cat "/home/${ADMIN_USER}/.ssh/${MAINT_USER}_id_rsa.pub")

if [[ -z ${ADMIN_PUB_KEY} ]] || [[ -z ${MAINT_PUB_KEY} ]]; then
	echo "Admin or maintenance user ssh public key does not exist."
	exit 1
fi

# Perform some checks on the control machine
if ! which -q sshpass; then
	echo "Install sshpass before running this script."
elif ! which -q expect; then
	echo "Install expect before running this script."
fi

/usr/bin/expect << EOF
	#!/usr/bin/expect -f
	spawn ssh -o ${SSH_OPTS} ${DEFAULT_USER}@${CURRENT_IP}
	expect "password:"
	send "${DEFAULT_PASS}\r"
	expect "password:"
	send "${DEFAULT_PASS}\r"
	expect "password:"
	send "${TEMP_PASS}\r"
	expect "password:"
	send "${TEMP_PASS}\r"
EOF

# Add administrator account
sshpass -p ${TEMP_PASS} ssh -tt -o ${SSH_OPTS} "${DEFAULT_USER}@${CURRENT_IP}" << EOF
	echo ${TEMP_PASS} | sudo -S echo "Adding administrator account"
	sudo useradd -d /home/${ADMIN_USER} -m -G ${GROUP_LIST} -s /bin/bash -U ${ADMIN_USER}
	sudo mkdir -p /home/${ADMIN_USER}/.ssh
	sudo echo "${ADMIN_PUB_KEY}" >> authorized_keys 
	sudo mv authorized_keys /home/${ADMIN_USER}/.ssh/authorized_keys
	sudo chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh
	sudo sed -i 's/ENABLED=1/ENABLED=0' /etc/default/motd-news
EOF

# Add maintenance account
sshpass -p ${TEMP_PASS} ssh -tt "${DEFAULT_USER}@${CURRENT_IP}"} << EOF
	echo ${TEMP_PASS} | sudo -S echo "Adding Ansible maintenance account"
	sudo useradd -d /home/${MAINT_USER} -m -s /bin/bash -r ${MAINT_USER}
	sudo mkdir -p /home/${MAINT_USER}/.ssh
	echo "${MAINT_PUB_KEY}" >> authorized_keys
	sudo mv authorized_keys /home/${MAINT_USER}/.ssh/authorized_keys 
	sudo chown -R ${MAINT_USER}:${MAINT_USER} /home/${MAINT_USER}/.ssh
EOF

# Add maintenance account to sudoers file and disable default user from having sudoers permissions
sshpass -p ${TEMP_PASS} ssh -tt "${DEFAULT_USER}@${CURRENT_IP}" << EOF
	echo ${TEMP_PASS} | sudo -S echo "Setting sudoers permissions"
	sudo echo -e "# User rules for ${MAINT_USER} service account\n${MAINT_USER} ALL=(ALL) NOPASSWD:ALL" > 90-${MAINT_USER}-permissions
	sudo chown 0:0 90-${MAINT_USER}-permissions
	sudo chmod 440 90-${MAINT_USER}-permissions
	sudo mv 90-${MAINT_USER}-permissions /etc/sudoers.d/90-${MAINT_USER}-permissions
	sudo mv ${DEFAULT_SUDOERS} ${DEFAULT_SUDOERS}~
EOF

# Set the hostname and static IP for the device, install the updates, and reboot
sshpass -p ${TEMP_PASS} ssh -tt "${DEFAULT_USER}@${CURRENT_IP}" << EOF
	echo ${TEMP_PASS} | sudo -S echo "Setting hostname, static IP, and installing updates"
	sudo hostnamectl set-hostname ${HOST_NAME}
	echo 'network: {config: disabled}' | sudo dd of=/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
	echo ${NET_CFG} | sudo dd of=/etc/netplan/50-cloud-init.yaml
	sudo netplan apply
	sudo apt-get update -yqq && sudo apt-get upgrade -yqq 2>&1 >> /dev/null
	echo "Enabling dynamic MOTD"
	sudo sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/motd-news
	echo "Rebooting, please stand by..."
	sudo reboot
EOF

# Sleep while we wait for the system to come back up
sleep 5 # this is to make sure we don't ping before the system has gone down
while :; do
	if ping -c 1 "${CURRENT_IP}" | grep '64 bytes from'; then
		break
	fi
	echo "..."
	sleep 5
done

# Run Kubernetes Playbook
echo "Initiating Ansible playbook..."
sleep 5
#ansible-playbook -i ../hosts.yml ../playbooks/kube_nodes.yml -v
