#!/bin/bash

#TODO Fix shared folders

set -e

TOOLDIR=~/.local/share/vm_manage
REMEMBER_FILE=$TOOLDIR/vm_remembered
SSH_KEYS=$TOOLDIR/ssh_keys

mkdir -p $TOOLDIR
touch $REMEMBER_FILE

##### Arguments parser

die()
{
	local _ret="${2:-1}"
	test "${_PRINT_HELP:-no}" = yes && print_help >&2
	echo "$1" >&2
	exit "${_ret}"
}


begins_with_short_option()
{
	local first_option all_short_options='h'
	first_option="${1:0:1}"
	test "$all_short_options" = "${all_short_options/$first_option/}" && return 1 || return 0
}

_positionals=()
VM_NAME=
VM_USER=
VM_IP=
REMEMBER="on"
START_TMUX="on"


print_help()
{
	printf '%s\n' "Starts a Virtualbox machine, must have an ip to connect to in SSH"
	printf 'Usage: %s [--user <arg>] [--ip <arg>] [--(no-)remember] [--(no-)start-tmux] [-h|--help] <name>\n' "$0"
	printf '\t%s\n' "-h, --help: Prints help"
}


parse_commandline()
{
	_positionals_count=0
	while test $# -gt 0
	do
		_key="$1"
		case "$_key" in
			--user)
				test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
				VM_USER="$2"
				shift
				;;
			--user=*)
				VM_USER="${_key##--user=}"
				;;
			--ip)
				test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
				VM_IP="$2"
				shift
				;;
			--ip=*)
				VM_IP="${_key##--ip=}"
				;;
			--no-remember|--remember)
				REMEMBER="on"
				test "${1:0:5}" = "--no-" && REMEMBER="off"
				;;
			--no-start-tmux|--start-tmux)
				START_TMUX="on"
				test "${1:0:5}" = "--no-" && START_TMUX="off"
				;;
			-h|--help)
				print_help
				exit 0
				;;
			-h*)
				print_help
				exit 0
				;;
			*)
				_last_positional="$1"
				_positionals+=("$_last_positional")
				_positionals_count=$((_positionals_count + 1))
				;;
		esac
		shift
	done
}


handle_passed_args_count()
{
	local _required_args_string="'name'"
	test "${_positionals_count}" -ge 1 || _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require exactly 1 (namely: $_required_args_string), but got only ${_positionals_count}." 1
	test "${_positionals_count}" -le 1 || _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect exactly 1 (namely: $_required_args_string), but got ${_positionals_count} (the last one was: '${_last_positional}')." 1
}


assign_positional_args()
{
	local _positional_name _shift_for=$1
	_positional_names="VM_NAME "

	shift "$_shift_for"
	for _positional_name in ${_positional_names}
	do
		test $# -gt 0 || break
		eval "$_positional_name=\${1}" || die "Error during argument parsing, possibly an Argbash bug." 1
		shift
	done
}

parse_commandline "$@"
handle_passed_args_count
assign_positional_args 1 "${_positionals[@]}"

##### ARGUMENTS SET UP

WAIT_VM_RUNNING(){
    sleep 5;
    while [[ ! $(vboxmanage list runningvms|grep "$VM_NAME") ]]
    do
        sleep 1;
    done
}


REMEMBERED=
# Load from remember
if [[ -z $VM_IP && -z $VM_USER ]]; then
    if [[ $(grep $VM_NAME $REMEMBER_FILE) ]]; then
        #LOAD FROM REMEMBER
        VM_IP=$(cat $REMEMBER_FILE|grep $VM_NAME|cut -d ',' -f 3)
        VM_USER=$(cat $REMEMBER_FILE|grep $VM_NAME|cut -d ',' -f 2)
        REMEMBERED="yes"
    else
        echo "VM $VM_NAME doesn't exist, create it or use the one remembered from previous usages"
        echo "VM remembered: "

        #TODO format to list
        echo $(cat $REMEMBER_FILE|awk -F ',' '{print $1}')
        exit 1;
    fi
elif [[ -z $VM_IP || -z $VM_USER ]]; then
    #ERROR MESSAGE
    echo "You have to pass the VM username AND IP address in order to connect to it"
    exit 1
fi
echo $VM_NAME $VM_USER $VM_IP
echo $REMEMBER $START_TMUX

SSH_ARG="$VM_USER@$VM_IP"








if [[ ! $(vboxmanage list runningvms|grep "$VM_NAME") ]]; then
    echo "[*] VM $VM_NAME not running, starting..."
    VBoxManage startvm $VM_NAME --type headless
    WAIT_VM_RUNNING
fi

if [ ! -f $SSH_KEYS ]; then
    echo "[*] No SSH keys generated, generating some ..."
    ssh-keygen -f $SSH_KEYS -N ''
    ssh $SSH_ARG "mkdir -p /home/$VM_USER/.ssh/"
    scp $SSH_KEYS.pub $SSH_ARG:/home/$VM_USER/.ssh/authorized_keys
fi

SSH_CMD="ssh -i $SSH_KEYS $SSH_ARG"


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

# Install VBoxAdditions
CHECK_INSTALLED 'virtualbox-guest-additions-iso'
if [ ! $? ]; then
    echo "Installing Virtualbox Guest Additions (and reboot)"
    $SSH_CMD -t 'sudo apt install virtualbox-guest-additions-iso && sudo reboot'
    echo "[*] Waiting for VM to reboot"
    WAIT_VM_RUNNING
fi


if [[ ($REMEMBER == "on") && (-z $REMEMBERED) ]]; then
    cat $REMEMBER_FILE | grep -v $VM_NAME > $REMEMBER_FILE
    echo "$VM_NAME,$VM_USER,$VM_IP" >> $REMEMBER_FILE
fi

# Start session

if [[ $START_TMUX == "off" ]]; then
    $SSH_CMD
else
    CHECK_INSTALLED 'tmux'
    if [ ! $? ]; then
        echo "[*] Tmux not installed on remote machine, simple ssh"
        $SSH_CMD
    else
        echo "[*] Starting ssh with tmux"
        scp -i $SSH_KEYS /etc/tmux.conf $SSH_ARG:/home/$VM_USER/.tmux.conf
        $SSH_CMD -t "tmux"
    fi
fi
