#!/bin/bash
#
# Performs basic systems administration tasks, as specified in the argument

if [[ $# -eq 0 || $1 == "--help" || $1 == '-h' ]]; then
    echo "Usage: configure_hosts.sh CONFIGFILE"
    exit 0
fi

if [ ! -r $1 ]; then
    echo "Can't read config file $1. Exiting." 1>&2
fi

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ HELPERS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Thanks Linux Journal June 2008
# http://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

die_on_failure () {
    if [ $? -ne 0 ]; then
        echo '***' $1 1>&2
        rm $BATCH_FILE
        exit 1
    fi
}
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ HELPERS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ TEST CONFIG ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Get configuration parameters
source $1

echo "*** Checking configuration parameters..."

for host in $HOSTS; do
    if ! ( valid_ip $host ) ; then
        echo "*** Host $host is not valid. Make sure hosts are in numeric IP format." 1>&2
        exit 1
    fi
done

if [[ ${WORKING_DIRECTORY:0:1} != '/' && ! $WORKING_DIRECTORY =~ ' ' ]]; then
    echo "*** WORKING_DIRECTORY is invalid. Defaulting to /tmp." 1>&2
    WORKING_DIRECTORY='/tmp'
fi

if [[ ! -z "${REMOTE_DIRECTORIES[@]}" ]]; then
    for dir in "${REMOTE_DIRECTORIES[@]}"; do
        if [[ ${dir:0:1} != '/' && ! $dir =~ ' ' ]]; then  # absolute, no spaces
            echo "*** REMOTE_DIRECTORIES must use absolute paths. Exiting." 1>&2
            exit 1
        fi
    done
fi

if [[ ! -z "${REMOTE_CONFIGURATIONS[@]}" ]]; then
    for pair in "${REMOTE_CONFIGURATIONS[@]}"; do
        filename=${pair% *}
        dir=${pair#* }
        if [[ ${dir:0:1} != '/'  && ! $dir =~ ' ' ]]; then
            echo "*** REMOTE_CONFIGURATIONS must use absolute paths. Exiting." 1>&2
            exit 1
        fi
        if [[ ! -r $filename ]]; then
            echo "*** REMOTE_CONFIGURATIONS file $filename doesn't exist! Exiting." 1>&2
            exit 1
        fi
    done
fi

echo "*** Configuration file is okay."


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~ CREATE BATCH FILE ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "*** Creating batch file..."
BATCH_FILE=`mktemp`


# Change working directory
echo "echo \"--> cd $WORKING_DIRECTORY\"" > $BATCH_FILE
echo "cd $WORKING_DIRECTORY" >> $BATCH_FILE

# Install some packages
if [[ ! -z $APTITUDE_PACKAGES ]]; then
    echo "echo \"--> apt-get install $APTITUDE_PACKAGES\"" >> $BATCH_FILE
    echo "apt-get install $APTITUDE_PACKAGES" >> $BATCH_FILE
fi

# Create some directories
if [[ ! -z "${REMOTE_DIRECTORIES[@]}" ]]; then
    for dir in "${REMOTE_DIRECTORIES[@]}"; do
        echo "echo \"--> mkdir -p $dir\"" >> $BATCH_FILE
        echo "mkdir -p $dir" >> $BATCH_FILE
    done
fi

CONFIG_FILES=()
# Install some config files
if [[ ! -z "${REMOTE_CONFIGURATIONS[@]}" ]]; then
    for pair in "${REMOTE_CONFIGURATIONS[@]}"; do
        filename=${pair% *}
        dir=${pair#* }
        echo "echo \"--> mv $filename $dir\"" >> $BATCH_FILE
        echo "mv $filename $dir" >> $BATCH_FILE
    
        CONFIG_FILES+=($filename)  # Keep track of our config files
    done
fi

# Run remote commands. Since these are user-provided, they might fail, so 
# immediately exit if that happens.
for comm in "${REMOTE_COMMANDS[@]}"; do
    echo "echo \"--> $comm\"" >> $BATCH_FILE
    echo "$comm" >> $BATCH_FILE
    echo 'if [ $? -ne 0 ]; then echo "Previous command failed, terminating"; exit 1; fi' >> $BATCH_FILE
done

# Clean up after ourselves; we'll always name this file config.sh
echo "rm $WORKING_DIRECTORY/config.sh" >> $BATCH_FILE

echo "*** Batch file created"


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~ EXECUTE COMMANDS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

for host in $HOSTS; do
    echo "*** Configuring host $host ***"
    echo "*** Copying over ssh key..."
    ssh-copy-id -i $ID root@$host

    echo "*** Copying over configuration files..."
    ssh root@$host "mkdir -p $WORKING_DIRECTORY"
    scp $BATCH_FILE root@$host:$WORKING_DIRECTORY/config.sh
    die_on_failure "Failed to copy over batch file. Exiting."

    if [[ ! -z "${CONFIG_FILES[@]}" ]]; then
        scp ${CONFIG_FILES[@]} root@$host:$WORKING_DIRECTORY
        die_on_failure "Failed to copy over configuration files. Exiting."
    fi

    echo -e "\n*** Applying configuration to remote machine..."
    ssh root@$host "bash $WORKING_DIRECTORY/config.sh"
    die_on_failure "Remote execution failed. Exiting."

    if [ ! -z "${TEST_COMMANDS[@]}" ]; then
        echo "*** Running test commands..."
        for comm in "${TEST_COMMANDS[@]}"; do
            echo $comm
            if [[ $comm ]]; then
                echo "*** Test succeeded."
            else
                echo "*** Test failed." 1>&2
            fi
        done
    fi
done

rm $BATCH_FILE
