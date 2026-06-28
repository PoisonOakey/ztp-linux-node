#!/bin/bash
# ==============================================================================
# Script: 02-provision-node.sh
# Description: Automates the provisioning of a VirtualBox Ubuntu Server node.
# ==============================================================================

# --- VARIABLES (Update these if hardware or paths change) ---
VM_NAME="SRE-Node-01"
OS_TYPE="Ubuntu_64"
RAM_MB=4096
CPU_CORES=2
DISK_SIZE_MB=25600
BRIDGE_ADAPTER="YOUR_COPIED_WIFI_NAME_HERE"
ISO_PATH="$HOME/server-lab/ubuntu-24.04.4-live-server-amd64.iso"
DISK_PATH="$HOME/server-lab/${VM_NAME}.vdi"
VBOX_MANAGE="/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"

echo "Starting Stage 1: Node Provisioning for $VM_NAME..."

# 1. Create and Register the VM Shell
echo "-> Creating Virtual Machine architecture..."
"$VBOX_MANAGE" createvm --name "$VM_NAME" --ostype "$OS_TYPE" --register

# 2. Allocate Hardware Resources
echo "-> Allocating $CPU_CORES vCPUs and ${RAM_MB}MB RAM..."
"$VBOX_MANAGE" modifyvm "$VM_NAME" --memory $RAM_MB --cpus $CPU_CORES

# 3. Configure Network Bridging
echo "-> Bridging network interface to $BRIDGE_ADAPTER..."
"$VBOX_MANAGE" modifyvm "$VM_NAME" --nic1 bridged
"$VBOX_MANAGE" modifyvm "$VM_NAME" --bridgeadapter1 "$BRIDGE_ADAPTER"

# 4. Provision Storage and Mount Media
echo "-> Provisioning ${DISK_SIZE_MB}MB Storage Drive..."
"$VBOX_MANAGE" createmedium disk --filename "$DISK_PATH" --size $DISK_SIZE_MB

echo "-> Attaching SATA Controller..."
"$VBOX_MANAGE" storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAHCI
"$VBOX_MANAGE" storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$DISK_PATH"

echo "-> Attaching IDE Controller and Mounting ISO..."
"$VBOX_MANAGE" storagectl "$VM_NAME" --name "IDE Controller" --add ide
"$VBOX_MANAGE" storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$ISO_PATH"

# 5. Boot the Node
echo "-> Infrastructure provisioned. Booting node in HEADLESS mode..."
"$VBOX_MANAGE" startvm "$VM_NAME" --type headless

echo "=================================================="
echo "Deployment triggered successfully."
echo "Wait 2 minutes for the OS to initialize, then check your router or run:"
echo "'$VBOX_MANAGE' guestproperty enumerate \"$VM_NAME\" to find your assigned IP."
