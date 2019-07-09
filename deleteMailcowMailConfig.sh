#!/bin/bash
source config.env
if [ "$MCHOST" == "" ] || [ "$MCPORT" == "" ]; then
	echo Copy config.env.template to config.env and edit it to suit your needs
	exit 1
fi
echo -n "Enter mailcow API key: "
read APIKEY
# Check for requires external programs
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
# List all aliases
apiRes=$(curl -s http://$MCHOST:$MCPORT/api/v1/get/alias/all -H "X-API-Key: $APIKEY")
rcCode=$?
if [ "$rcCode" != 0 ]; then
	echo Failed to list aliases: $apiRes
	exit $rcCode
fi
postdata=$(echo "$apiRes" | jq -cr '[.[].id]')
if [ "$postdata" != "[]" ]; then
	apiRes=$(curl -s -X POST "http://$MCHOST:$MCPORT/api/v1/delete/alias" -d items="$postdata" -H "X-API-Key: $APIKEY")
	rcCode=$?
	if [ "$rcCode" != 0 ] || [ $(echo "$apiRes" | jq -r 'if type == "array" then .[0].type else .type end') != "success" ]; then
		echo Failed to delete aliases $postdata: $apiRes
		exit $rcCode
	else
		echo Successfully deleted aliases $postdata
	fi
else
	echo No aliases to delete
fi
# List all mailboxes
apiRes=$(curl -s http://$MCHOST:$MCPORT/api/v1/get/mailbox/all -H "X-API-Key: $APIKEY")
rcCode=$?
if [ "$rcCode" != 0 ]; then
	echo Failed to list mailboxes: $apiRes
	exit $rcCode
fi
postdata=$(echo "$apiRes" | jq -cr '[.[].username]')
if [ "$postdata" != "[]" ]; then
	apiRes=$(curl -s -X POST http://$MCHOST:$MCPORT/api/v1/delete/mailbox -d items="$postdata" -H "X-API-Key: $APIKEY")
	rcCode=$?
	if [ "$rcCode" != 0 ] || [ $(echo "$apiRes" | jq -r 'if type == "array" then .[0].type else .type end') != "success" ]; then
		echo Failed to delete mailboxes $postdata: $apiRes
		exit $rcCode
	else
		echo Successfully deleted mailboxes $postdata
	fi
else
	echo No mailboxes to delete
fi
# List all domains
apiRes=$(curl -s http://$MCHOST:$MCPORT/api/v1/get/domain/all -H "X-API-Key: $APIKEY")
rcCode=$?
if [ "$rcCode" != 0 ]; then
	echo Failed to list domains: $apiRes
	exit $rcCode
fi
postdata=$(echo "$apiRes" | jq -cr '[.[].domain_name]')
if [ "$postdata" != "[]" ]; then
	apiRes=$(curl -s -X POST http://$MCHOST:$MCPORT/api/v1/delete/domain -d items="$postdata" -H "X-API-Key: $APIKEY")
	rcCode=$?
	if [ "$rcCode" != 0 ] || [ $(echo "$apiRes" | jq -r 'if type == "array" then .[0].type else .type end') != "success" ]; then
		echo Failed to delete domains $postdata: $apiRes
		exit $rcCode
	else
		echo Successfully deleted domains $postdata
	fi
else
	echo No domains to delete
fi
