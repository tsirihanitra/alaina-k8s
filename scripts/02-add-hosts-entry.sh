#!/usr/bin/env bash
# Ajoute (ou met à jour) l'entrée alaina.local dans /etc/hosts,
# pointée vers l'IP du contrôleur Ingress de Minikube.
set -euo pipefail

DOMAIN="alaina.local"

# Avec le driver docker, l'IP à utiliser est en général 127.0.0.1
# via `minikube tunnel`, MAIS on peut aussi utiliser l'IP donnée par
# `minikube ip` si l'addon ingress est actif sans tunnel (driver docker
# sur Linux route parfois directement). On tente minikube ip d'abord.
IP=$(minikube ip 2>/dev/null || echo "")

if [ -z "$IP" ]; then
  echo "Impossible de récupérer l'IP via 'minikube ip'."
  echo "Si tu utilises 'minikube tunnel', utilise 127.0.0.1 à la place."
  exit 1
fi

echo "==> IP Minikube détectée : $IP"

if grep -q "$DOMAIN" /etc/hosts; then
  echo "==> Entrée existante trouvée, mise à jour..."
  sudo sed -i "/$DOMAIN/d" /etc/hosts
fi

echo "$IP $DOMAIN" | sudo tee -a /etc/hosts
echo "==> Fait. Vérifie avec : cat /etc/hosts | grep $DOMAIN"
