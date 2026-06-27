# Laptop-as-Server
## #0 Disable Conflicting Feautures
Open PowerShell as Adminstartor and run these commands. Otherwise it will cause the VM to hang when it's booting up.
```
# Disable Hyper-V
Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

# Disable the Windows Hypervisor Platform
Disable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform

# Disable Virtual Machine Platform
Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
```
<br>

## #1 Quick Start
Install Oracle.Virtual Box using Git Bash (use ```apt``` on Ubuntu or ```brew``` on Mac):
```
winget install -e --id Oracle.VirtualBox
```
Then, create an folder & move into it:
```
mkdir -p ~/server-lab
cd ~/server-lab
```
Retrive Ubuntu 24.04 LTS Server ISO from its release servers. Use ```-O``` to keep the original name & ```-L``` to follow any redirects just in case:
```
curl -O -L https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso
```
After finish downloading (around 2.6GB), verify it:
```
ls -lh
```
<br>

## #2 Setup Virtual Machine
Make sure you are clear with your VirtualBox directory:
<img width="1277" height="706" alt="image" src="https://github.com/user-attachments/assets/a070ec42-75ea-4c2a-b186-59b5714587bf" />
<br>
<br>

Next, identify your Host Network Adapter from you bridged interfaces:
```
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list bridgedifs
```

It should look something like this:
> [!CAUTION]
> **Make sure you never disclose it to anyone:**
<img width="947" height="496" alt="image" src="https://github.com/user-attachments/assets/ff0b729d-cd5a-4c46-8e06-7f2d508e562a" />
<br>
<br>

Copy the name of the network adapter after ```Name: ```. In this case it would be ```Intel(R) Wi-Fi 6 AX201 160MHz```
<br>

Create the VM hardware architecture, assigning 4GB RAM and 2 CPU cores:
```
# Create and reguster the VM shell
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" createvm --name "SRE-Node-01" --ostype "Ubuntu_64" --register

# Modify the hardware allocation
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm "SRE-Node-01" --memory 4096 --cpu 2
```

Create a virtual NIC and bind it to your actual network adapter. Replace ```YOUR_COPIED_WIFI_NAME_HERE``` with the name of the network adapter name: 
```
# Enable virtual NIC and set it to bridged mode
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm "SRE-Node-01" --nic1 bridged

# Bind virtual NIC to actual network adapter
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm "SRE-Node-01" --bridgeadapter1 "YOUR_COPIED_WIFI_NAME_HERE"
```

Create a virtual hard drive and mount the Ubuntu ISO image:
```
# Create a 25GB virtual hard drive inside your server-lab folder
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" createmedium disk --filename ~/server-lab/SRE-Node-01.vdi --size 25600

# Add a SATA storage controller and attach your virtual hard drive
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" storagectl "SRE-Node-01" --name "SATA Controller" --add sata --controller IntelAHCI
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" storageattach "SRE-Node-01" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium ~/server-lab/SRE-Node-01.vdi

# Add an IDE storage controller and mount the Ubuntu Server ISO file
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" storagectl "SRE-Node-01" --name "IDE Controller" --add ide
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" storageattach "SRE-Node-01" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium ~/server-lab/ubuntu-24.04.4-live-server-amd64.iso
```
<br>

## #3 Power On the Machine
Boot the VM system:
```
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" startvm "SRE-Node-01" --type gui
```

A separate window will pop up. Use keyboard to select ```Try or Install Ubuntu Server``` in the GRUB bootloader:
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/e4c1f1f2-33be-4594-b5d7-1bed85562ab4" />





