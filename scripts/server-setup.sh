#!/bin/bash

function display_help {
	echo -e "\nUsage: ./server-setup.sh -[a|d|g|i|m]"
	echo -e "\t-a: Target IP address (what you want the node to be set to)"
	echo -e "\t-d: Distribution (ubuntu|raspbian)"
	echo -e "\t-H: Hostname"
	echo -e "\t-i: Current IP (dhcp assigned IP when node first spins up)"
	echo -e "\t-m: Maintenance user name"
	echo -e "\t-u: Admin user name"
	echo -e "\t-h: Display this help"
	exit 1
}

while getopts ":a:d:h:H:i:m:u:" opt
do
	case "${opt}" in
		a ) TARGET_IP=${OPTARG};;
		d ) DISTRO=${OPTARG};;
		H ) HOST_NAME=${OPTARG};;
		i ) CURRENT_IP=${OPTARG};;
		m ) MAINT_USER=${OPTARG};;
		u ) ADMIN_USER=${OPTARG};;
		h ) display_help;;
		* ) display_help;;
	esac
done

# Check user inputs and set defaults if not passed
if [[ $OPTIND -eq 1 ]]; then
	display_help
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
if [[ -z $IP_ADDR ]]; then
	echo "Please specify the IP address for the target device."
	exit 1
fi
if [[ -z $MAINT_USER ]]; then
	MAINT_USER="ansible"
	echo "Using default of ansible for maintenance user."
fi

# Set some defaults
SSH_OPTS="StrictHostKeyChecking=no"
TEMP_PASS="TempPass123"

# Install some required packages on the control machine

if uname -a | grep -iq manjaro; then
	sudo pacman -Syu sshpass expect --noconfirm >> /dev/null
fi
if uname -a | grep -iq ubuntu; then
	sudo apt install -yqq sshpass expect >> /dev/null
fi

# Set up to automatically pull the public SSH keys
ADMIN_PUB_KEY="$(cat /home/${ADMIN_USER}/.ssh/id_rsa.pub)"
MAINT_PUB_KEY="$(cat /home/${ADMIN_USER}/.ssh/${MAINT_USER}_id_rsa.pub)"

if [[ -z ${ADMIN_PUB_KEY} ]] || [[ -z ${MAINT_PUB_KEY} ]]; then
	echo "Admin or maintenance user ssh public key does not exist."
	exit 1
fi

# Set distro specific variables
if [[ ${DISTRO} == "ubuntu" ]]; then
	DEFAULT_USER="ubuntu"
	DEFAULT_PASS="ubuntu"
	GROUP_LIST="sudo,adm,dialout,cdrom,floppy,audio,dip,video,plugdev,netdev,lxd"
	DEFAULT_SUDOERS="/etc/sudoers.d/90-cloud-init-users"
	UPDATE_COMMAND="apt-get update -yqq && sudo apt-get upgrade -yqq 2>&1 >> /dev/null"
	DISABLE_MOTD="sed -i 's/ENABLED=1/ENABLED=0' /etc/default/motd-news"
	ENABLE_MOTD="sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/motd-news"
fi
if [[ ${DISTRO} == "raspbian" ]]; then
	DEFAULT_USER="pi"
	DEFAULT_PASS="raspberry"
	GROUP_LIST=""
	DEFAULT_SUDOERS=""
	UPDATE_COMMAND="sudo apt update && sudo apt upgrade -y"
fi

/usr/bin/expect << EOF
	#!/usr/bin/expect -f
	spawn ssh -o ${SSH_OPTS} ${DEFAULT_USER}@${IP_ADDR}
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
sshpass -p ${TEMP_PASS} ssh -o ${SSH_OPTS} ${DEFAULT_USER}@"${CURRENT_IP}" << EOF
	echo ${TEMP_PASS} | sudo -S echo "Adding administrator account"
	sudo useradd -d /home/${ADMIN_USER} -m -G ${GROUP_LIST} -s /bin/bash -U ${ADMIN_USER}
	sudo mkdir -p /home/${ADMIN_USER}/.ssh
	sudo echo ${ADMIN_PUB_KEY} >> authorized_keys 
	sudo mv authorized_keys /home/${ADMIN_USER}/.ssh/authorized_keys
	sudo chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh
	sudo ${DISABLE_MOTD}
EOF

# Add maintenance account
sshpass -p ${TEMP_PASS} ssh ${DEFAULT_USER}@"${CURRENT_IP}"} << EOF
	echo ${TEMP_PASS} | sudo -S echo "Adding Ansible maintenance account"
	sudo useradd -d /home/${MAINT_USER} -m -s /bin/bash -r ${MAINT_USER}
	sudo mkdir -p /home/${MAINT_USER}/.ssh
	echo $MAINT_PUB_KEY} >> authorized_keys
	sudo mv authorized_keys /home/${MAINT_USER}/.ssh/authorized_keys 
	sudo chown -R ${MAINT_USER}:${MAINT_USER} /home/${MAINT_USER}/.ssh
EOF

# Add maintenance account to sudoers file and disable default user from having sudoers permissions
sshpass -p ${TEMP_PASS} ssh ${DEFAULT_USER}@"${CURRENT_IP}" << EOF
	echo ${TEMP_PASS} | sudo -S echo "Setting sudoers permissions"
	sudo echo -e "# User rules for ${MAINT_USER} service account\n${MAINT_USER} ALL=(ALL) NOPASSWD:ALL" > 90-${MAINT_USER}-permissions
	sudo chown 0:0 90-${MAINT_USER}-permissions
	sudo chmod 440 90-${MAINT_USER}-permissions
	sudo mv 90-${MAINT_USER}-permissions /etc/sudoers.d/90-${MAINT_USER}-permissions
	sudo mv ${DEFAULT_SUDOERS} ${DEFAULT_SUDOERS}~
EOF

# Set the hostname for the device, install the updates, and reboot
sshpass -p ${TEMP_PASS} ssh ${DEFAULT_USER}@"${CURRENT_IP}" << EOF
	echo ${TEMP_PASS} | sudo -S echo "Setting hostname and installing updates"
	sudo hostnamectl set-hostname ${HOST_NAME}
	sudo ${UPDATE_COMMAND}
	echo "Enabling dynamic MOTD"
	sudo ${ENABLE_MOTD}
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
#ansible-playbook -i ../hosts.yml kube_nodes.yml -v
