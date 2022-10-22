#! /bin/bash

# notes on provisioning grafana
# 	- https://grafana.com/tutorials/provision-dashboards-and-data-sources/
# 	- https://grafana.com/docs/grafana/v9.0/setup-grafana/configure-docker/

apt-get -y update &&\
apt-get -y install software-properties-common wget apt-transport-https

# add stable and beta versions of OSS grafana
wget -q -O /usr/share/keyrings/grafana.key https://packages.grafana.com/gpg.key

echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" |\
tee -a /etc/apt/sources.list.d/grafana.list

echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb beta main" |\
tee -a /etc/apt/sources.list.d/grafana.list

# install grafana to instance via apt package repo
apt-get -y update && apt-get -y install grafana

# enable grafana to run on startup via systemctl...
systemctl daemon-reload &&\
systemctl start grafana-server &&\
systemctl enable grafana-server.service

# does xyz...
mkdir -p /usr/share/grafana/conf/provisioning/datasources/ \
	/usr/share/grafana/conf/provisioning/dashboards/\
	/var/lib/grafana/dashboards/wikipedia/

chown -R ubuntu /usr/share/grafana/conf/provisioning/datasources/\
	/usr/share/grafana/conf/provisioning/dashboards/\
	/var/lib/grafana/dashboards/wikipedia/

# should resolve to `/var/lib/grafana/dashboards/wikipedia/`
mkdir -p ${GRAFANA_INSTANCE_DASHBOARDS_DIR}${GRAFANA_INSTANCE_DASHBOARDS_GROUP} 
chown -R ubuntu ${GRAFANA_INSTANCE_DASHBOARDS_DIR}${GRAFANA_INSTANCE_DASHBOARDS_GROUP}

# install athena and mysql (default) plugins
grafana-cli plugins install grafana-athena-datasource 2.2.0 &&\
systemctl restart grafana-server
