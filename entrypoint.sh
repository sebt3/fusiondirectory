#!/bin/sh

if ! [ -f /var/web/version ] || ! diff /fusiondirectory/version /var/web/version;then
	cp -Rapf /fusiondirectory/* /var/web/
fi

LDAP_DOMAIN=${LDAP_DOMAIN:-"example.com"}
LDAP_BASE_DN="${LDAP_BASE_DN:-"$(echo $LDAP_DOMAIN|sed 's/^/dc=/;s/\./,dc=/g')"}"
LDAP_HOST=${LDAP_HOST:-"ldap"}
LDAP_CONFIG_PASSWORD=${LDAP_CONFIG_PASSWORD:-"config"}
LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASSWORD:-"admin"}

CNT=0
while ! ldapsearch -LLL -h ${LDAP_HOST} -D 'cn=admin,cn=config' -w ${LDAP_CONFIG_PASSWORD} -b $LDAP_BASE_DN >/dev/null 2>&1; do
	echo "Waiting for the directory to be ready ($((CNT+=1)))"
	sleep 2
done

# Finalise FD base install
if [ -d /var/web/plugins/config/dhcp ];then # one of the plugins
	echo -e 'www-data'|fusiondirectory-setup --set-fd_home="/var/web" --write-vars --update-cache
else
	echo -e '/usr/share/fusiondirectory-plugins-1.3.tar.gz\nwww-data'|fusiondirectory-setup --set-fd_home="/var/web" --write-vars --install-plugins --update-locales --update-cache
fi
sed -i 's#define("SMARTY".*#define("SMARTY", "/usr/local/lib/php/smarty3/Smarty.class.php");#' /var/web/include/variables.inc

# Install missing schemas
if ! fusiondirectory-insert-schema -o "-h ${LDAP_HOST} -D 'cn=admin,cn=config' -w ${LDAP_CONFIG_PASSWORD}" -l|grep -q core-fd-conf;then
	echo "Loading fusiondirectory default schemas"
	fusiondirectory-insert-schema -o "-h ${LDAP_HOST} -D 'cn=admin,cn=config' -w ${LDAP_CONFIG_PASSWORD}"
fi
for ext in samba sudo rfc2307bis personal-fd mail-fd systems-fd alias-fd applications-fd calEntry calRessources dovecot-fd samba-fd-conf sudo-fd-conf personal-fd-conf mail-fd-conf systems-fd-conf alias-fd-conf applications-fd-conf;do
	if ! fusiondirectory-insert-schema -o "-h ${LDAP_HOST} -D 'cn=admin,cn=config' -w ${LDAP_CONFIG_PASSWORD}" -l|grep -q ${ext};then
		echo "Loading $ext schema"
	        fusiondirectory-insert-schema -o "-h ${LDAP_HOST} -D 'cn=admin,cn=config' -w ${LDAP_CONFIG_PASSWORD}" -i ${ext}.schema
	fi
done

# Looking for missing piece in the ddirectory
counter() {	ldapsearch -LLL -h $LDAP_HOST -w $LDAP_ADMIN_PASSWORD -D cn=admin,$LDAP_BASE_DN "$@" 2>/dev/null |wc -l; }
Lapply() {	ldapmodify -h $LDAP_HOST -w $LDAP_ADMIN_PASSWORD -D cn=admin,$LDAP_BASE_DN; }
B64() {		echo -n "$@"|base64; }
if [ $(counter  -b $LDAP_BASE_DN "(objectClass=organization)") -eq 0 ];then
	echo "ERROR: Something is very wrong with your directory !!!"
	FORCE_CONFIG=1
else
if [ $(counter -b $LDAP_BASE_DN "(& (objectClass=gosaDepartment) (objectClass=organization))") -eq 0 ];then
	Lapply <<END
dn: $LDAP_BASE_DN
changetype: modify
add: ou
ou: ${LDAP_DOMAIN}
-
add: description
description: ${LDAP_DOMAIN}
-
add: objectClass
objectClass: gosaDepartment
-
add: objectClass
objectClass: gosaAcl
-
add: GOSAACLENTRY
GOSAACLENTRY: 0:subtree:$(B64 cn=admin,ou=aclroles,$LDAP_BASE_DN):$(B64 uid=fd-admin,ou=people,$LDAP_BASE_DN)
END
fi
if [ $(counter -b ou=fusiondirectory,$LDAP_BASE_DN) -eq 0 ];then
	Lapply <<END
dn: ou=fusiondirectory,$LDAP_BASE_DN
changetype: add
ou: fusiondirectory
objectClass: organizationalUnit

dn: cn=config,ou=fusiondirectory,$LDAP_BASE_DN
changetype: add
objectClass: fusionDirectoryConf
FDLANGUAGE: en_US
FDTHEME: breezy
FDTIMEZONE: America/New_York
FDLDAPSIZELIMIT: 200
FDMODIFICATIONDETECTIONATTRIBUTE: entryCSN
FDLOGGING: TRUE
FDSCHEMACHECK: TRUE
FDENABLESNAPSHOTS: TRUE
FDSNAPSHOTBASE: ou=snapshots,$LDAP_BASE_DN
FDWILDCARDFOREIGNKEYS: TRUE
FDPASSWORDDEFAULTHASH: ssha
FDFORCEPASSWORDDEFAULTHASH: FALSE
FDHANDLEEXPIREDACCOUNTS: FALSE
FDLOGINATTRIBUTE: uid
FDFORCESSL: FALSE
FDWARNSSL: TRUE
FDSESSIONLIFETIME: 1800
FDHTTPAUTHACTIVATED: FALSE
FDHTTPHEADERAUTHACTIVATED: FALSE
FDHTTPHEADERAUTHHEADERNAME: AUTH_USER
FDSSLKEYPATH: /etc/ssl/private/fd.key
FDSSLCERTPATH: /etc/ssl/certs/fd.cert
FDSSLCACERTPATH: /etc/ssl/certs/ca.cert
FDCASACTIVATED: FALSE
FDCASSERVERCACERTPATH: /etc/ssl/certs/ca.cert
FDCASHOST: localhost
FDCASPORT: 443
FDCASCONTEXT: /cas
FDACCOUNTPRIMARYATTRIBUTE: uid
FDCNPATTERN: %givenName% %sn%
FDSTRICTNAMINGRULES: TRUE
FDUSERRDN: ou=people
FDACLROLERDN: ou=aclroles
FDRESTRICTROLEMEMBERS: FALSE
FDSPLITPOSTALADDRESS: FALSE
FDDISPLAYERRORS: FALSE
FDLDAPSTATS: FALSE
FDDEBUGLEVEL: 0
FDLISTSUMMARY: TRUE
FDACLTABONOBJECTS: FALSE
FDDISPLAYHOOKOUTPUT: FALSE
cn: config
END
fi

if [ $(counter -b ou=aclroles,$LDAP_BASE_DN) -eq 0 ];then
	Lapply <<END
dn: ou=aclroles,$LDAP_BASE_DN
changetype: add
ou: aclroles
objectClass: organizationalUnit

dn: cn=admin,ou=aclroles,$LDAP_BASE_DN
changetype: add
objectClass: top
objectClass: gosaRole
cn: admin
description: Gives all rights on all objects
GOSAACLTEMPLATE: 0:all;cmdrw

dn: cn=manager,ou=aclroles,$LDAP_BASE_DN
changetype: add
cn: manager
description: Give all rights on users in the given branch
objectClass: top
objectClass: gosaRole
GOSAACLTEMPLATE: 0:user/user;cmdrw,user/posixAccount;cmdrw

dn: cn=editowninfos,$LDAP_BASE_DN
changetype: add
cn: editowninfos
description: Allow users to edit their own basic information
objectClass: top
objectClass: gosaRole
GOSAACLTEMPLATE: 0:user/user;srw,user/posixAccount;srw

dn: cn=editownpwd,ou=aclroles,$LDAP_BASE_DN
changetype: add
cn: editownpwd
description: Allow users to edit their own password
objectClass: top
objectClass: gosaRole
GOSAACLTEMPLATE: 0:user/user;s#userPassword;rw
END
fi

if [ $(counter -b uid=fd-admin,ou=people,$LDAP_BASE_DN) -eq 0 ];then
	Lapply <<END
dn: uid=fd-admin,ou=people,$LDAP_BASE_DN
changetype: add
cn: System Administrator
sn: Administrator
givenName: System
uid: fd-admin
userPassword:: $(slappasswd -s $LDAP_ADMIN_PASSWORD|base64)
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
END
fi
fi

cat >/etc/fusiondirectory/fusiondirectory.conf <<ENDF
<?xml version="1.0"?>
<conf>
  <main default="default"
        logging="TRUE"
        displayErrors="FALSE"
        forceSSL="FALSE"
        templateCompileDirectory="/var/spool/fusiondirectory/"
        debugLevel="0"
    >

    <!-- Location definition -->
    <location name="default"
    >
        <referral URI="ldap://${LDAP_HOST}:389" base="${LDAP_BASE_DN}"
                        adminDn="cn=admin,${LDAP_BASE_DN}"
                        adminPassword="${LDAP_ADMIN_PASSWORD}" />
    </location>
  </main>
</conf>
ENDF
chgrp www-data /etc/fusiondirectory/fusiondirectory.conf
chmod 640 /etc/fusiondirectory/fusiondirectory.conf

if [ ${FORCE_CONFIG:-"0"} -eq 1 ];then
	echo "Forcing configuration"
	#mv /etc/fusiondirectory/fusiondirectory.conf /etc/fusiondirectory/fusiondirectory.conf.orig
fi

echo "Starting $@"
exec "$@"
