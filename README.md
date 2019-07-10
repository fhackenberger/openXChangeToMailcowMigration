# OpenXChange to mailcow migration scripts

A few scripts to migrate a simple OpenXChange 6.0 mail setup to mailcow (2019-07-03)

## Documentation

Here's an overview of the available scripts:

* *openXchangeSetupToCsv.sh* Connects to the OpenXChange mysql DB and exports .csv files
* *csvToMailcowAPI.sh* Reads .csv and an /etc/alias file and creates domains, mailboxes, aliases and forwarding rules on mailcow
* *importOpenXchangeMails.sh* Uses *openXchangeToDovecotTarball.sh* to import mails from OpenXChange
* *openXchangeToDovecotTarball.sh* Exports OpenXChange cyrus mail storage to a tarball
* *deleteMailcowMailConfig.sh* Deletes all aliases, mailboxes and domains from a mailcow installation (useful during testing)

This is what I used to migrate my set-up:
```
cp config.env.template config.env
vi config.env # Edited the variables to suit my environment
scp openXchangeSetupToCsv.sh openXchangeToDovecotTarball.sh openxchange.mydomain.com:
ssh openxchange.mydomain.com
$ mkdir mailcow-migration
$ git clone https://github.com/a-schild/cyrus2dovecot.git
$ chmod +x openXchangeSetupToCsv.sh openXchangeToDovecotTarball.sh
$ ./openXchangeSetupToCsv.sh
# Entered password, as stored in e.g. /etc/postfix/ox_domains.cf
$ exit
scp openxchange.mydomain.com:"mailcow-migration/*.csv" .
scp openxchange.mydomain.com:/etc/aliases etc_aliases
# Got the API key from mailcow using the admin login
./csvToMailcowAPI.sh
./importOpenXchangeMails.sh root@openxchange.mydomain.com
```
