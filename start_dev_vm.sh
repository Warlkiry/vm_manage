VM_NAME=Devenv
VM_USER="debian"
VM_IP="192.168.57.3"
SSH_ARG="$VM_USER@$VM_IP"

#TODO Fix shared folders

WAIT_VM_RUNNING(){
    sleep 5;
    while [[ ! $(vboxmanage list runningvms|grep "$VM_NAME") ]]
    do
        sleep 1;
    done
}

set -e
if [[ ! $(vboxmanage list runningvms|grep "$VM_NAME") ]]; then
    echo "[*] VM $VM_NAME not running, starting..."
    VBoxManage startvm $VM_NAME --type headless
    WAIT_VM_RUNNING
fi

if [ ! -f ./ssh_vm_key ]; then
    echo "[*] No SSH keys generated, generating some ..."
    ssh-keygen -f ./ssh_vm_key -N ''
    ssh $SSH_ARG "mkdir -p /home/$VM_USER/.ssh/"
    scp ./ssh_vm_key.pub $SSH_ARG:/home/$VM_USER/.ssh/authorized_keys
fi

SSH_CMD="ssh -i ./ssh_vm_key $SSH_ARG"


CHECK_INSTALLED(){
    echo "$1 installed ?"
    set +e
    if [[ $($SSH_CMD "dpkg -l $1 2>&1" | grep $1 | grep -v 'dpkg-query:') ]]; then
        echo "Installed"
        return 1;
    else
        echo "Not installed"
        return 0;
    fi
    set -e
}

CHECK_INSTALLED 'virtualbox-guest-additions-iso'
if [ ! $? ]; then
    $SSH_CMD -t 'sudo apt install virtualbox-guest-additions-iso && sudo reboot'
    echo "[*] Waiting for VM to reboot"
    WAIT_VM_RUNNING
fi

CHECK_INSTALLED 'tmux'
if [ ! $? ]; then
    echo "[*] Tmux not installed on remote machine, simple ssh"
    $SSH_CMD
else
    echo "[*] Starting ssh with tmux"
    scp -i ./ssh_vm_key /etc/tmux.conf $SSH_ARG:/home/$VM_USER/.tmux.conf
    $SSH_CMD -t "tmux"
fi
