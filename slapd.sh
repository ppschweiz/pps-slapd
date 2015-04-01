#!/bin/bash

set -eu
initldif="/slapd/init/init.ldif"
importldif="/slapd/import.ldif"

status () {
  echo "---> ${@}" >&2
}

set -x
: LDAP_ROOTPASS=${LDAP_ROOTPASS}
: LDAP_DOMAIN=${LDAP_DOMAIN}
: LDAP_ORGANISATION=${LDAP_ORGANISATION}

if [ ! -e /var/lib/ldap/docker_bootstrapped ]; then
  status "configuring slapd for first run"

  cat <<EOF | debconf-set-selections
slapd slapd/internal/generated_adminpw password ${LDAP_ROOTPASS}
slapd slapd/internal/adminpw password ${LDAP_ROOTPASS}
slapd slapd/password2 password ${LDAP_ROOTPASS}
slapd slapd/password1 password ${LDAP_ROOTPASS}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORGANISATION}
slapd slapd/backend string HDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean true
slapd slapd/dump_database select when needed
EOF

  dpkg-reconfigure -f noninteractive slapd
SLAPD_CONF="/etc/ldap/slapd.d"
  rm -rf ${SLAPD_CONF}/cn=config ${SLAPD_CONF}/cn=config.ldif
  rm -rf ${SLAPD_CONF}
  mkdir -p /var/lib/ldap/slapd.d
  ln -s /var/lib/ldap/slapd.d ${SLAPD_CONF}
  #mkdir -p ${SLAPD_CONF}

  #slapcat -F /etc/ldap/slapd.d -b "cn=config"
backend=hdb
backendobjectclass=olcHdbConfig
adminpass=$LDAP_ROOTPASS
basedn="dc=`echo $LDAP_DOMAIN | sed 's/^\.//; s/\./,dc=/g'`"
	# Change some defaults
	sed -i -e "s|@BACKEND@|$backend|g" ${initldif}
	sed -i -e "s|@BACKENDOBJECTCLASS@|$backendobjectclass|g" ${initldif}
	sed -i -e "s|@SUFFIX@|$basedn|g" ${initldif}
	sed -i -e "s|@PASSWORD@|$adminpass|g" ${initldif}
  slapadd -F /etc/ldap/slapd.d -b "cn=config" -l ${initldif}
  slapadd -F /etc/ldap/slapd.d -b "cn=config" -l /slapd/init/pps.ldif
  slapadd -F /etc/ldap/slapd.d -b "cn=config" -l /slapd/init/x-pps.ldif
  touch ${importldif}
  slapadd -F /etc/ldap/slapd.d -l ${importldif}
  chown -R openldap.openldap /var/lib/ldap
  chown -R openldap.openldap /etc/ldap

  touch /var/lib/ldap/docker_bootstrapped
else
  status "found already-configured slapd"
fi

status "starting slapd"
set -x
exec /usr/sbin/slapd -h "ldap:///" -u openldap -g openldap -d 0
