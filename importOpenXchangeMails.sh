#!/bin/bash
# Exports mails using cyrus2dovecot and a script on a remote system
source config.env
if [ "$MCHOST" == "" ] || [ "$MCPORT" == "" ]; then
	echo Copy config.env.template to config.env and edit it to suit your needs
	exit 1
fi
oxUserHost=$1
if [ "$oxUserHost" == "" ]; then
	echo Specificy something like username@example.com as the first argument
	exit 1
fi
oxHostExportScript=$2
if [ "$oxHostExportScript" == "" ]; then
	oxHostExportScript=/manual_installs/cyrus2dovecot-master/openXchange2mailcow.sh
fi

declare -a emailsToConvert
declare -A emailToUsername
# We do this loop first, because using ssh with -tt seems to conflict with this
while IFS='|' read -r Address Domain UserName Description; do
        if [ ! ${DOMAINS["$Domain"]+_} ]; then
                continue;
        fi
	if [ ${SKIPUSERS["$Address"]+_} ]; then
		echo Skipping $Address mailbox as it is in SKIPUSERS
		continue;
	fi
	emailsToConvert+=($Address)
	emailToUsername["$Address"]="$UserName"
done < <(sed -e 's/";"/|/g' -e 's/^"//' -e 's/"$//' users.csv) # Runs the while loop in this shell to update the array, as opposed to using $ cat bla.txt | while xxx; do ... done
for Address in "${emailsToConvert[@]}"; do
	userName=${emailToUsername["$Address"]}
	domain=$(echo "$Address" | sed 's/.*@//');
	localname=$(echo "$Address" | sed 's/@.*//');
	echo Exporting email on ${oxHost} for $Address with username $userName
	tarball=$(ssh -tt ${oxUserHost} "$oxHostExportScript $Address $userName" | tr -d '\r\n')
        rcCode=$?
        if [ "$rcCode" != 0 ]; then
                echo Failed to export mails for $Address
                exit $rcCode
        fi
	localTarball=$(echo "$tarball" | sed "s/.*\///")
	echo Copying $tarball from $oxHost
	scp "${oxUserHost}:$tarball" "$localTarball"
        rcCode=$?
        if [ "$rcCode" != 0 ]; then
                echo Failed to copy tarball: $tarball
                exit $rcCode
        fi
	tar --directory=/var/lib/docker/volumes/mailcowdockerized_vmail-vol-1/_data -xf "$localTarball"
        rcCode=$?
        if [ "$rcCode" != 0 ]; then
                echo Failed to extract tarball: $localTarball to /var/lib/docker/volumes/mailcowdockerized_vmail-vol-1/_data
                exit $rcCode
        fi
	chown -R 5000:5000 /var/lib/docker/volumes/mailcowdockerized_vmail-vol-1/_data/$domain/;
	rm $localTarball
        echo Successfully copied email for $Address
done
