#!/bin/bash

function display_help {
       echo -e "\nUsage: ./worksation-setup.sh -[a|d|H|m|h]"
       echo -e "\t-a: Admin user name"
       echo -e "\t-d: Distribution (arch)"
       echo -e "\t-H: Hostname"
       echo -e "\t-m: Maintenance user name"
       echo -e "\t-h: Display this help"
       exit 1
}

while getopts ":a:d:h:H:i:m:" opt
do
	case "${opt}" in
		a ) ADMIN_USER=${OPTARG};;
		d ) DISTRO=${OPTARG};;
		H ) HOST_NAME=${OPTARG};;
		m ) MAINT_USER=${OPTARG};;
		h ) display_help;;
	esac
done

if [[ $OPTIND -eq ]]; then
	display_help
fi
if [[ -z $ADMIN_USER ]]; then
	ADMIN_USER="sean"
	echo "Using default of sean for admin user name."
fi
if [[ -z $DISTRO ]]; then
	echo "Please set distro with -d switch."
	exit 1
fi
if [[ -z $HOST_NAME ]]; then
	HOST_NAME="nephilim"
	echo "Using default of nephilim for host name."
fi
if [[ -z $MAINT_USER ]]; then
	MAINT_USER="ansible"
	echo "Using default of ansible for maintenance user."
fi

ADMIN_PUB_KEY="$(cat /home/${ADMIN_USER}/.ssh/id_rsa.pub)"
MAINT_PUB_KEY="$(cat /home/${ADMIN_USER}/.ssh/${MAINT_USER}_id_rsa.pub)"

if [[ -z ${ADMIN_PUB_KEY} ]] || [[ -z ${MAINT_PUB_KEY} ]]; then
	echo "Admin or maintenance user ssh public key does not exist."
	exit 1
fi


