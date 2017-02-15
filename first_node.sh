#!/bin/bash

thisip=$(hostname -I | cut -d ' ' -f1)

read -p "Node Name: " nodename
read -p "Database Password: " dbasepass
read -p "Total Number of Nodes: " totalnode
echo "IP Address of this node is $thisip "


ip[1]=$thisip

nodenumber=$(($totalnode-1))
c=2
for i in $(seq $nodenumber);
do
    read -p "Node $(($i+1)) IP Address: " ipadd;
    eval ip[$(($i+1))]=$ipadd;
    c=$((c+1));
done

read -p "What is the FQDN of this Node: " domainname
read -p "Username for this Node: " username
read -p "Password for this Node: " userpass
read -p "What is your email address: " email

#database details
database_host=127.0.0.1
database_port=5432
database_username=fusionpbx

apt-get update && apt-get upgrade -y --force-yes && apt-get install -y --force-yes git  && cd /usr/src && git clone https://github.com/fusionpbx/fusionpbx-install.sh.git && chmod 755 -R /usr/src/fusionpbx-install.sh && cd /usr/src/fusionpbx-install.sh/debian

sed '16,19 s/^/#/' -i /usr/src/fusionpbx-install.sh/debian/resources/postgres.sh
sed '22,27 s/^#//' -i /usr/src/fusionpbx-install.sh/debian/resources/postgres.sh

 ./install.sh && rm /etc/fusionpbx/config.php


for i in $(seq $totalnode)
do
  iptables -A INPUT -j ACCEPT -p tcp --dport 5432 -s ${ip[$i]}/32
  iptables -A INPUT -j ACCEPT -p tcp --dport 8080 -s ${ip[$i]}/32
  iptables -A INPUT -j ACCEPT -p tcp --dport 4444 -s ${ip[$i]}/32
done
#answer the questions for iptables persistent
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

sed -i /etc/postgresql/9.4/main/postgresql.conf -e s:'snakeoil.key:snakeoil-postgres.key:'
cp /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/private/ssl-cert-snakeoil-postgres.key
chown postgres:postgres /etc/ssl/private/ssl-cert-snakeoil-postgres.key
chmod 600 /etc/ssl/private/ssl-cert-snakeoil-postgres.key


cat >> /etc/postgresql/9.4/main/postgresql.conf << EOF
listen_addresses = '*'
shared_preload_libraries = 'bdr'
wal_level = 'logical'
track_commit_timestamp = on
max_connections = 200
max_wal_senders = 10
max_replication_slots = 10
# max_replication_slots maximum possible number is 48
# Make sure there are enough background worker slots for BDR to run
max_worker_processes = 20

# These aren't required, but are useful for diagnosing problems
#log_error_verbosity = verbose
#log_min_messages = debug1
#log_line_prefix = 'd=%d p=%p a=%a%q '

# Useful options for playing with conflicts
#bdr.default_apply_delay=2000   # milliseconds
#bdr.log_conflicts_to_table=on
#bdr.skip_ddl_replication = off
EOF

echo "host     all     all     127.0.0.1/32     trust" >> /etc/postgresql/9.4/main/pg_hba.conf

for i in $(seq $totalnode)
do
  echo "hostssl     all     all     ${ip[$i]}/32     trust" >> /etc/postgresql/9.4/main/pg_hba.conf
done

for i in $(seq $totalnode)
do
  echo "hostssl     replication     postgres     ${ip[$i]}/32     trust" >> /etc/postgresql/9.4/main/pg_hba.conf
done


systemctl daemon-reload
systemctl restart postgresql

#sudo -u postgres psql -c "DROP DATABASE fusionpbx";
#sudo -u postgres psql -c "DROP DATABASE freeswitch";
#sudo -u postgres psql -c "CREATE DATABASE fusionpbx";
#sudo -u postgres psql -c "CREATE DATABASE freeswitch";
#sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fusionpbx to fusionpbx;"
#sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE freeswitch to fusionpbx;"
#sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE freeswitch to freeswitch;"
sudo -u postgres psql -c "ALTER USER fusionpbx WITH PASSWORD '$dbasepass';"
sudo -u postgres psql -c "ALTER USER freeswitch WITH PASSWORD '$dbasepass';"
sudo -u postgres psql -d fusionpbx -c "CREATE EXTENSION btree_gist;"
sudo -u postgres psql -d fusionpbx -c "CREATE EXTENSION bdr;"
sudo -u postgres psql -d freeswitch -c "CREATE EXTENSION btree_gist;"
sudo -u postgres psql -d freeswitch -c "CREATE EXTENSION bdr;"
sudo -u postgres psql -d fusionpbx -c "SELECT bdr.bdr_group_create(local_node_name := '$nodename', node_external_dsn := 'host=$thisip port=5432 dbname=fusionpbx connect_timeout=10 keepalives_idle=5 keepalives_interval=1 sslmode=require');"
sudo -u postgres psql -d fusionpbx -c "SELECT bdr.bdr_node_join_wait_for_ready();"
#sudo -u postgres psql -d fusionpbx -c "CREATE EXTENSION pgcrypto;"
sudo -u postgres psql -d freeswitch -c "SELECT bdr.bdr_group_create(local_node_name := '$nodename', node_external_dsn := 'host=$thisip port=5432 dbname=freeswitch connect_timeout=10 keepalives_idle=5 keepalives_interval=1 sslmode=require');"
sudo -u postgres psql -d freeswitch -c "SELECT bdr.bdr_node_join_wait_for_ready();"
#sudo -u postgres psql -d freeswitch -c "CREATE EXTENSION pgcrypto;"




cd /usr/src
git clone https://github.com/fusionpbx/fusionpbx-apps 
cp -R fusionpbx-apps/bdr /var/www/fusionpbx/app
chown -R www-data:www-data /var/www/fusionpbx/app/bdr

mkdir -p /etc/fusionpbx/resources/templates/
cp -R /var/www/fusionpbx/resources/templates/provision /etc/fusionpbx/resources/templates
chown -R www-data:www-data /etc/fusionpbx


sh -c 'echo "deb http://linux-packages.getsync.com/btsync/deb btsync non-free" > /etc/apt/sources.list.d/btsync.list'
wget -qO - https://linux-packages.resilio.com/resilio-sync/key.asc | sudo apt-key add -
apt-get update
apt-get install btsync

sed -i '8,9s/btsync/www-data/' /lib/systemd/system/btsync.service
sed -i '15s/btsync:btsync/www-data:www-data/' /lib/systemd/system/btsync.service

chown -R www-data:www-data /var/lib/btsync
systemctl daemon-reload
systemctl restart btsync
systemctl enable btsync


echo "postgress password $PGPASSWORD"


