#!/bin/bash
chownUser=$(whoami)
DIR="$(dirname "$(readlink -f "$0")")"
email=$1
username=$2
localname=$(echo "$email" | sed 's/@.*//');
domain=$(echo "$email" | sed 's/^.*@//');
cyrusdir=$(echo "$username" | sed -e 's/\./^/g')
cd $DIR
mkdir -p mailcow-data
sudo rm -Rf mailcow-data/$domain/$localname
sudo rm -Rf mailcow-data/$email.tar.gz
sudo ./cyrus2dovecot/cyrus2dovecot --cyrus-inbox="/var/spool/cyrus/mail/%h/user/%u" --cyrus-seen="/var/lib/cyrus/user/%h/%u.seen" --cyrus-sub="/var/lib/cyrus/user/%h/%u.sub" --dovecot-inbox="$DIR/mailcow-data/$domain/$localname/Maildir" $cyrusdir > /dev/null;
rcCode=$?
if [ $rcCode != 0 ]; then
	echo cyrus2dovecot failed to run for $cyrusdir
	exit $rcCode;
fi
sudo tar --directory=mailcow-data -czf mailcow-data/$email.tar.gz $domain/$localname/Maildir;
sudo chown $chownUser mailcow-data/$email.tar.gz
echo $DIR/mailcow-data/$email.tar.gz
exit 0;
