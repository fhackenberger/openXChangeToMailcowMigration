# OpenXChange to mailcow migration scripts

A few scripts to migrate a simple OpenXChange 6.0 mail setup to mailcow

## Documentation

Here's an overview of the available scripts:

* *openXchangeSetupToCsv.sh* Connects to the OpenXChange mysql DB and exports .csv files
* *csvToMailcowAPI.sh* Reads .csv and an /etc/alias file and creates domains, mailboxes, aliases and forwarding rules on mailcow
* *importOpenXchangeMails.sh* Uses *deleteMailcowMailConfig.sh* to import mails from OpenXChange
* *openXchange2mailcow.sh* Exports OpenXChange cyrus mail storage to a tarball
* *deleteMailcowMailConfig.sh* Deletes all aliases, mailboxes and domains from a mailcow installation (useful during testing)

This is what I used to migrate my set-up:
```
cp config.env.template config.env
vi config.env # Edited the variables to suit my environment
scp openXchangeSetupToCsv.sh openXchange2mailcow.sh openxchange.mydomain.com:
ssh openxchange.mydomain.com
$ mkdir mailcow-migration
$ chmod +x openXchangeSetupToCsv.sh openXchange2mailcow.sh
$ ./openXchangeSetupToCsv.sh
# Entered password, as stored in e.g. /etc/postfix/ox_domains.cf
$ exit
scp openxchange.mydomain.com:"mailcow-migration/*.csv" .
scp openxchange.mydomain.com:/etc/aliases etc_aliases
# Got the API key from mailcow using the admin login
./csvToMailcowAPI.sh
./importOpenXchangeMails.sh openxchange.mydomain.com openXchange2mailcow.sh
```
