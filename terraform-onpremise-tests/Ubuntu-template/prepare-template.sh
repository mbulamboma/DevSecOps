#!/bin/bash
###############################################################################
# prepare-template.sh
#
# Prépare la VM template Ubuntu pour le clonage via vmrest :
#   1) Réécrit /etc/netplan/00-installer-config.yaml avec dhcp-identifier: mac
#      correctement indenté sous l'interface ens33 (sinon les clones avec
#      MAC unique demandent quand même la même IP DHCP).
#   2) Vide /etc/machine-id (systemd en regénère un au premier boot du clone)
#      pour que les clones aient des identités systemd distinctes.
#   3) Nettoie cloud-init s'il est présent.
#   4) Éteint la VM proprement.
#
# Lancé depuis Windows via plink :
#   pscp ... prepare-template.sh ubuntu@<ip>:/tmp/
#   plink ... ubuntu@<ip> "echo root | sudo -S bash /tmp/prepare-template.sh"
###############################################################################
set -euo pipefail

NETPLAN=/etc/netplan/00-installer-config.yaml

echo "[1/4] Réécriture de $NETPLAN ..."
cat >"$NETPLAN" <<'YAML'
# This is the network config written by 'subiquity'
# Modifié pour le clonage : dhcp-identifier: mac force le DHCP client-id
# à utiliser l'adresse MAC (régénérée par VMware sur chaque clone) plutôt
# que /etc/machine-id, garantissant ainsi des IPs uniques par clone.
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: true
      dhcp6: true
      dhcp-identifier: mac
YAML
chmod 600 "$NETPLAN"

echo "[1/4] Validation netplan ..."
netplan generate

echo "[2/4] Reset /etc/machine-id ..."
truncate -s 0 /etc/machine-id
# /var/lib/dbus/machine-id est déjà un symlink vers /etc/machine-id (vérifié),
# rien à faire de plus.

echo "[3/4] Nettoyage cloud-init (si présent) ..."
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init clean --logs --seed || true
fi

echo "[4/4] Préparation OK. Extinction dans 5s ..."
sync
sleep 5
shutdown -h now
