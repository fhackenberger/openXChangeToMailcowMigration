#!/bin/bash
mysql -u openexchange -p open-xchange-db << EOF
SELECT domainName INTO OUTFILE '/home/fhackenberger/mailcow-migration/domains.csv' FIELDS TERMINATED BY ';' ENCLOSED BY '"' LINES TERMINATED BY '\n' FROM  mail_domains;
SELECT mail, SUBSTRING_INDEX(mail,'@',-1) as domain, (select uid from login2user lu where lu.id = u.id) as login, c.field01 as name INTO OUTFILE '/home/fhackenberger/mailcow-migration/users.csv' FIELDS TERMINATED BY ';' ENCLOSED BY '"' LINES TERMINATED BY '\n' FROM user u join prg_contacts c on u.id=c.userid;
SELECT value,u.mail INTO OUTFILE '/home/fhackenberger/mailcow-migration/aliases.csv' FIELDS TERMINATED BY ';' ENCLOSED BY '"' LINES TERMINATED BY '\n' from user u join user_attribute ua on ua.id = u.id where ua.name = 'alias' and value != u.mail;
EOF
