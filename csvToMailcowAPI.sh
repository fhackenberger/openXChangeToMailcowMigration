#!/bin/bash
source config.env
if [ "$MCHOST" == "" ] || [ "$MCPORT" == "" ]; then
	echo Copy config.env.template to config.env and edit it to suit your needs
	exit 1
fi
echo -n "Enter mailcow API key: "
read APIKEY
# Check for requires external programs
pwgen -y 10 > /dev/null 2>&1
rcCode=$?
if [ "$rcCode" != 0 ]; then
	echo Please install pwgen
	exit 1;
fi
curl --version > /dev/null 2>&1
rcCode=$?
if [ "$rcCode" != 0 ]; then
	echo Please install curl
	exit 1;
fi
jq --version > /dev/null 2>&1
rcCode=$?
if [ "$rcCode" != 0 ]; then
	echo Please install jq
	exit 1;
fi
# Create the domains
declare -A domains
while IFS='|' read -r Domain; do
	if [ ! ${DOMAINS["$Domain"]+_} ]; then
		echo Skipping domain $Domain
		continue;
	fi
	domains["$Domain"]=true
done < <(sed -e 's/";"/|/g' -e 's/^"//' -e 's/"$//' domains.csv) # Runs the while loop in this shell to update the array, as opposed to using $ cat bla.txt | while xxx; do ... done
domainNr=1
for Domain in "${!domains[@]}"; do
	# We need to restart SoGo when creating the last domain to allow later logins with the new mailboxes
	postdata="\"domain\":\"$Domain\",\"description\":\"$Domain\",\"aliases\":\"50\",\"mailboxes\":\"50\",\"defquota\":\"3072\",\"maxquota\":\"10240\",\"quota\":\"153600\",\"active\":\"1\",\"rl_value\":\"1\",\"rl_frame\":\"s\"}"
	if [ $domainNr == ${#domains[@]} ]; then
		postdata="{\"restart_sogo\":\"1\",$postdata";
	else
		postdata="{$postdata";
	fi
	apiRes=$(curl -s -X POST http://$MCHOST:$MCPORT/api/v1/add/domain -d attr="$postdata" -H "X-API-Key: $APIKEY")
	rcCode=$?
	if [ "$rcCode" != 0 ] || [ $(echo "$apiRes" | jq -r 'if type == "array" then .[0].type else .type end') != "success" ]; then
		echo Failed to create domain $Domain: $apiRes
		echo Beware that you need to restart SoGo if other domains have been created successfully
		exit $rcCode
	fi
	echo Successfully created domain $Domain
	(( domainNr += 1))
done || exit $?
# There's no api, so we would have to login as an admin to mailcow, it's easier to ask the user to do that
echo Please restart SoGo now \(in mailcow admin\) as we added domains
# Create the DKIM keys
sed -e 's/";"/|/g' -e 's/^"//' -e 's/"$//' domains.csv | while IFS='|' read -r Domain; do
	if [ ! ${DOMAINS["$Domain"]+_} ]; then
		continue;
	fi
	postdata="{\"domains\":\"$Domain\",\"dkim_selector\":\"dkim\",\"key_size\":\"2048\"}"
	apiRes=$(curl -s -X POST http://$MCHOST:$MCPORT/api/v1/add/dkim -d attr="$postdata" -H "X-API-Key: $APIKEY")
	rcCode=$?
	if [ "$rcCode" != 0 ] || [ $(echo "$apiRes" | jq -r 'if type == "array" then .[0].type else .type end') != "success" ]; then
		echo Failed to create DKIM \(non fatal, key might be there already\) for domain $Domain: $apiRes
	else
		echo Successfully created DKIM key for domain $Domain
	fi
done || exit $?
# Create the mailboxes
declare -A mailboxPws # We will re-use passwords we've already used in the past / generated in previous runs
while IFS='|' read -r Address Password; do
	mailboxPws["$Address"]="$Password"
done < <(sed -e 's/";"/|/g' -e 's/^"//' -e 's/"$//' users_pw.csv) # Runs the while loop in this shell to update the array, as opposed to using $ cat bla.txt | while xxx; do ... done
declare -A mailboxes # Map of username to mailbox email address for later looups with aliases
declare -A createdMailboxes # Map of username to mailbox email address for later looups with aliases
while IFS='|' read -r Address Domain UserName Description; do
	mailboxes["$UserName"]="$Address";
	if [ ! ${DOMAINS["$Domain"]+_} ]; then
		continue;
	fi
	if [ ${SKIPUSERS["$Address"]+_} ]; then
		echo Skipping $Address mailbox as it is in SKIPUSERS
		continue;
	fi
	localPart=$(echo "$Address" | sed 's/@.*//');
	descEscaped=$(echo "$Description" | sed 's/ /+/g');
	userPw=${mailboxPws["$Address"]}
	if [ "$userPw" == "" ]; then
		userPw=$(pwgen 10 1 | sed 's/"/\\"/g');
		echo "\"$Address\";\"$userPw\"" >> users_pw.csv
	fi
	postdata="{\"local_part\":\"$localPart\",\"domain\":\"$Domain\",\"name\":\"$descEscaped\",\"quota\":\"3072\",\"password\":\"$userPw\",\"password2\":\"$userPw\",\"active\":\"1\"}";
	apiRes=$(curl -s -X POST http://$MCHOST:$MCPORT/api/v1/add/mailbox -d attr="$postdata" -H "X-API-Key: $APIKEY")
	rcCode=$?
	if [ "$rcCode" != 0 ] || [ $(echo "$apiRes" | jq -r 'if type == "array" then .[0].type else .type end') != "success" ]; then
		echo Failed to create mailbox $Address: $apiRes
		exit $rcCode
	fi
	mailboxPws["$Address"]="$userPw"
	createdMailboxes["$Address"]=true;
	echo Successfully created mailbox $Address
done < <(sed -e 's/";"/|/g' -e 's/^"//' -e 's/"$//' users.csv) # Runs the while loop in this shell to update the array, as opposed to using $ cat bla.txt | while xxx; do ... done
# Merge aliases from all sources
declare -A aliases
while IFS='|' read -r FromAddress ToAddresses; do # Read from etc_aliases (end of loop)
	if [ $FromAddress == "root" ]; then
		echo Ignoring alias for root
		continue;
	fi
	if [[ $FromAddress != *"@"* ]]; then
		if [ ! ${mailboxes["$FromAddress"]+_} ]; then
			echo "No mailbox found for username $FromAddress when creating alias to $ToAddress. Skipping it"
			continue;
		fi
		FromAddress=${mailboxes["$FromAddress"]};
	fi
	ToAddress=""
	while read -r NewToAddress; do
		if [ "$ToAddress" != "" ]; then
			ToAddress="$ToAddress,"
		fi
		if [[ $NewToAddress != *"@"* ]]; then
			NewToAddress=${mailboxes["$NewToAddress"]};
		fi
		ToAddress="${ToAddress}${NewToAddress}"
	done < <(echo "$ToAddresses" | sed 's/,/\n/g')
	currAliases=${aliases["$FromAddress"]};
	if [ "$currAliases" != "" ]; then
		currAliases="$currAliases,"
	fi
	currAliases="${currAliases}$ToAddress";
	aliases[$FromAddress]="$currAliases"
done < <(cat etc_aliases | sed -e 's/:\s\+/|/' -e 's/ /,/g' -e '/^#/d' -e '/^\s*$/d') # Runs the while loop in this shell to update the array, as opposed to using $ cat bla.txt | while xxx; do ... done
while IFS='|' read -r FromAddress ToAddress; do # Read from aliases.csv (end of loop)
	if [[ $FromAddress != *"@"* ]]; then
		if [ ! ${mailboxes["$FromAddress"]+_} ]; then
			echo "No email found for username $FromAddress when creating alias to $ToAddress. Skipping it"
			continue;
		fi
		FromAddress=${mailboxes["$FromAddress"]};
	fi
	if [[ $ToAddress != *"@"* ]]; then
		ToAddress=${mailboxes["$ToAddress"]};
	fi
	currAliases=${aliases["$FromAddress"]};
	if [ "$currAliases" != "" ]; then
		currAliases="$currAliases,"
	fi
	currAliases="${currAliases}$ToAddress";
	aliases[$FromAddress]="$currAliases"
done < <(sed -e 's/";"/|/g' -e 's/^"//' -e 's/"$//' aliases.csv)
# Actually create the aliases entries. Either as a mailcow mailbox alias or as a forwarding rule for an existing mailbox
for FromAddress in "${!aliases[@]}"; do
	domain=$(echo "$FromAddress" | sed 's/^.*@//');
	if [ ! ${DOMAINS["$domain"]+_} ]; then # Check if we need to skip this domain
		continue;
	fi
	toAddresses=${aliases["$FromAddress"]};
	declare -A toAddrMap=()
	while read -r ToAddr; do
		toAddrMap["$ToAddr"]=true
	done < <(echo "$toAddresses" | sed -e 's/,/\n/g') # Runs the while loop in this shell to update the array, as opposed to using $ cat bla.txt | while xxx; do ... done
	if [ ${createdMailboxes["$FromAddress"]+_} ]; then # Mailbox exists, need a forwarding rule
		postdata="{\"userName\":\"$FromAddress\",\"password\":\"${mailboxPws["$FromAddress"]}\",\"rememberLogin\":0}";
		curl -s --cookie-jar .sogo-api.cookies "http://$MCHOST:$MCPORT/SOGo/connect" -H 'Content-Type: application/json;charset=utf-8' --data "$postdata" > /dev/null
		rcCode=$?
		if [ "$rcCode" != 0 ]; then
			echo Failed to log into SoGo with $FromAddress
			exit $rcCode
		fi
		curl -s --cookie .sogo-api.cookies "http://$MCHOST:$MCPORT/SOGo/so/${FromAddress}/jsonSettings" > .sogo-settings.json
		if [ "$rcCode" != 0 ]; then
			echo Failed to get SoGo settings for $FromAddress
			exit $rcCode
		fi
		curl -s --cookie .sogo-api.cookies "http://$MCHOST:$MCPORT/SOGo/so/${FromAddress}/jsonDefaults" > .sogo-defaults.json
		if [ "$rcCode" != 0 ]; then
			echo Failed to get SoGo settings for $FromAddress
			exit $rcCode
		fi
		if [ ${toAddrMap["$FromAddress"]+_} ]; then # If the alias points to itself as well, we'll keep the email
			toAddrMapDef=$(declare -p toAddrMap)
			eval "${toAddrMapDef/ toAddrMap/ toAddrMapCopy}" # Copy the map to remove the FromAddress
			unset toAddrMapCopy[$FromAddress];
			forwardArrayStr=`echo ${!toAddrMapCopy[@]} | sed 's/ /","/g'`
			forwardArrayStr="[\"$forwardArrayStr\"]"
			forwardObjStr="{\"Forward\":{\"forwardAddress\":$forwardArrayStr,\"enabled\":1,\"keepCopy\":1}}" # Beware of spaces, 1:1 comparison below
		else # Otherwise we'll omit keepCopy:1, so mailcow will drop the email silently after forwarding
			forwardArrayStr=$(echo "[\"$toAddresses\"]" | sed 's/,/","/g')
			forwardObjStr="{\"Forward\":{\"forwardAddress\":$forwardArrayStr,\"enabled\":1}}" # Beware of spaces, 1:1 comparison below
		fi
		# Build the new preferences JSON
		sogoDefaults=$(cat .sogo-defaults.json | jq --compact-output --argjson forwardObj "$forwardObjStr" ". + \$forwardObj")
		{ echo '{"defaults": '; echo "$sogoDefaults"; echo ', "settings": '; cat .sogo-settings.json; echo '}'; } > .sogo-preferences.json
		# Set the new preferences
		curl -s --cookie .sogo-api.cookies "http://$MCHOST:$MCPORT/SOGo/so/${FromAddress}/Preferences/save" -H 'Content-Type: application/json;charset=utf-8' --data-binary @.sogo-preferences.json > /dev/null
		if [ "$rcCode" != 0 ]; then
			echo Failed to save SoGo preferences for $FromAddress
			exit $rcCode
		fi
		# Validate the new preferences, as the backend does not report errors properly
		newForwardObjStr=$(curl -s --cookie .sogo-api.cookies "http://$MCHOST:$MCPORT/SOGo/so/${FromAddress}/jsonDefaults" | jq -c '{Forward: .Forward}')
		if [ "$rcCode" != 0 ]; then
			echo Failed to get SoGo settings to validate forward for $FromAddress
			exit $rcCode
		else
			if [ "$newForwardObjStr" != "$forwardObjStr" ]; then
				echo "Failed to validate SoGo settings for forward: wanted $forwardObjStr got $newForwardObjStr"
				exit $rcCode
			fi
		fi
		rm .sogo-api.cookies .sogo-settings.json .sogo-defaults.json .sogo-preferences.json
		echo Successfully created forwarding rules from $FromAddress to $toAddresses
	else # Mailbox doesn't exist, we'll use a mailcow alias
		postdata="{\"active\":[\"0\",\"1\"],\"address\":\"$FromAddress\",\"goto\":\"$toAddresses\"}"
		apiRes=$(curl -s -X POST http://$MCHOST:$MCPORT/api/v1/add/alias -d attr="$postdata" -H "X-API-Key: $APIKEY")
		rcCode=$?
		if [ "$rcCode" != 0 ] || [ $(echo "$apiRes" | jq -r 'if type == "array" then .[0].type else .type end') != "success" ]; then
			echo Failed to create alias from $FromAddress to $toAddresses: $apiRes
			exit $rcCode
		fi
		echo "\"$FromAddress\";\"$toAddresses\"" >> aliases_mcow.csv
		echo Successfully created mailcow alias from $FromAddress to $toAddresses
	fi
done
