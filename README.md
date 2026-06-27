# Laptop-as-Server
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
<img width="1277" height="706" alt="image" src="https://github.com/user-attachments/assets/d57c50c8-a366-4df4-8467-71972e0bab90" />

Next, identify your Host Network Adapter from you bridged interfaces:
```
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list bridgedifs
```

It should look something like this:
> [!CAUTION]
> **Make sure you never disclose it to anyone:**
<img width="947" height="496" alt="image" src="https://github.com/user-attachments/assets/6e53d6fe-3706-4770-8cde-a952f00d1d5b" />

Create the VM hardware architecture, assigning 4GB RAM and 2 CPU cores:
```
# Create and reguster the VM shell
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" createvm --name "SRE-Node-01" --ostype "Ubuntu_64" --register

# Modify the hardware allocation
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm "SRE-Node-01" --memory 4096 --cpu 2
```






