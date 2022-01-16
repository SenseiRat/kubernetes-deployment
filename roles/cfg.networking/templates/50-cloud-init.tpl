# This file is generated from information provided by the datasource.  Changes
# to it will not persist across an instance reboot.  To disable cloud-init's
# network configuration capabilities, write a file
# /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg with the following:
# network: {config: disabled}
network:
    ethernets:
        eth0:
            dhcp4: false
            addresses: [{{ ansible_host }}/24]
            nameservers:
              addresses: [{{ local_dns }}]
            routes:
              - to: default
                via: {{ gateway_ip }}
            match:
                driver: bcmgenet
            optional: true
            set-name: eth0
    version: 2
