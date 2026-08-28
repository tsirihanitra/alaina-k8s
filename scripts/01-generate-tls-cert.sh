#!/usr/bin/env bash
# Génère un certificat auto-signé pour alaina.local et produit
# manifests/06-tls-secret.yaml (prêt à être commit dans le dépôt GitOps).
set -euo pipefail

DOMAIN="alaina.local"
OUT_DIR="$(dirname "$0")/../certs"
MANIFEST_DIR="$(dirname "$0")/../manifests"

mkdir -p "$OUT_DIR"

echo "==> Génération de la clé privée + certificat auto-signé pour $DOMAIN"
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout "$OUT_DIR/tls.key" \
  -out "$OUT_DIR/tls.crt" \
  -subj "/CN=${DOMAIN}/O=alaina-projet" \
  -addext "subjectAltName=DNS:${DOMAIN}"

echo "==> Encodage base64 et écriture du manifest Secret"
CRT_B64=$(base64 -w0 "$OUT_DIR/tls.crt")
KEY_B64=$(base64 -w0 "$OUT_DIR/tls.key")

cat > "$MANIFEST_DIR/06-tls-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: alaina-tls-secret
  namespace: alaina
type: kubernetes.io/tls
data:
  tls.crt: ${CRT_B64}
  tls.key: ${KEY_B64}
EOF

echo "==> OK. Fichier généré : $MANIFEST_DIR/06-tls-secret.yaml"
echo "==> N'oublie pas de l'ajouter à Git (git add manifests/06-tls-secret.yaml)"
