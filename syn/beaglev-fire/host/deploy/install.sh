#!/bin/sh
# Installs the CP-300 daemon on the BeagleV-Fire: run as root from the copied tree
#   sudo sh install.sh          (from  <tree>/syn/beaglev-fire/host/deploy)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../../.." && pwd)

mkdir -p /opt/cp300
cp -r "$TREE/syn" "$TREE/tools" /opt/cp300/
chown -R root:root /opt/cp300

# the daemon runs as beagle (member of kmem): let that group use the UIO device
echo 'SUBSYSTEM=="uio", GROUP="kmem", MODE="0660"' > /etc/udev/rules.d/99-cp300-uio.rules
udevadm control --reload
udevadm trigger --subsystem-match=uio

install -m 644 "$HERE/cp300d.service" /etc/systemd/system/cp300d.service
install -m 644 "$HERE/cp300.nginx.conf" /etc/nginx/snippets/cp300.conf
mkdir -p /usr/share/cockpit/cp300
cp "$HERE/cockpit/manifest.json" "$HERE/cockpit/index.html" /usr/share/cockpit/cp300/

# include the snippet in the default server block, once
if ! grep -q "snippets/cp300.conf" /etc/nginx/sites-enabled/default; then
	sed -i '0,/^[[:space:]]*server_name .*;/s//&\n\tinclude snippets\/cp300.conf;/' /etc/nginx/sites-enabled/default
fi
nginx -t
systemctl reload nginx
systemctl daemon-reload
systemctl enable --now cp300d
echo "CP-300: http://$(hostname)/cp300/  (also in the Cockpit sidebar under Tools)"
