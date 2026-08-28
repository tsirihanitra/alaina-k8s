# Déploiement du site « alaina » sur Kubernetes (Minikube) + GitOps ArgoCD

Ce dépôt contient le déploiement complet d'un site statique HTML/CSS sur un
cluster Kubernetes local (Minikube, driver Docker), exposé en HTTPS via un
Ingress avec certificat auto-signé, et géré en GitOps avec ArgoCD.

## Architecture

```
Navigateur --HTTPS--> Ingress (nginx-ingress + TLS) --> Service (ClusterIP)
                                                              |
                                                     ReplicaSet (3 pods nginx)
                                                              |
                                          ConfigMap (site HTML) + ConfigMap (conf nginx)

GitHub (ce dépôt) <--- ArgoCD (sync auto + self-heal) ---> Cluster Kubernetes
```

## Arborescence

```
alaina-k8s/
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 01-configmap-nginx-conf.yaml
│   ├── 02-configmap-site.yaml
│   ├── 03-replicaset.yaml
│   ├── 04-service.yaml
│   ├── 05-ingress.yaml
│   └── 06-tls-secret.yaml.template   (généré en 06-tls-secret.yaml par le script)
├── argocd/
│   └── application.yaml
├── scripts/
│   ├── 01-generate-tls-cert.sh
│   └── 02-add-hosts-entry.sh
└── site/
    └── index.html                    (source du site, déjà copié dans le ConfigMap)
```

---

## PHASE 0 — Prérequis

Installe (si ce n'est pas déjà fait) sur Parrot OS / Debian :

```bash
# Docker (driver de Minikube)
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker $USER && newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

**Vérification :**
```bash
docker --version
kubectl version --client
minikube version
```
Les trois commandes doivent afficher un numéro de version sans erreur.

---

## PHASE 1 — Démarrer le cluster Minikube

```bash
minikube start --driver=docker --cpus=2 --memory=4096
```

**Ce que fait cette commande :** elle crée un conteneur Docker qui joue le
rôle d'un nœud Kubernetes complet (control-plane + kubelet), télécharge les
images nécessaires, et configure `kubectl` pour pointer dessus automatiquement.

**Vérification (obligatoire avant de continuer) :**
```bash
minikube status
kubectl get nodes
```
Tu dois voir `host: Running`, `kubelet: Running`, `apiserver: Running`, et un
nœud `minikube` avec le statut `Ready`.

Active ensuite l'addon Ingress (contrôleur nginx-ingress géré par Minikube) :
```bash
minikube addons enable ingress
```

**Vérification :**
```bash
kubectl get pods -n ingress-nginx
```
Attends que le pod `ingress-nginx-controller-xxxxx` soit `Running` et `1/1
READY` (ça peut prendre 1-2 minutes la première fois — l'image se télécharge).

> **Dépannage courant :** si le pod reste `Pending`, regarde
> `kubectl describe pod -n ingress-nginx <nom-du-pod>` : la cause la plus
> fréquente est un manque de ressources (`--memory` trop bas au démarrage
> de Minikube) ou un pull d'image bloqué (vérifie ta connexion / proxy Docker).

---

## PHASE 2 — Déployer manuellement (pour comprendre, avant GitOps)

On applique les manifests un par un pour bien voir ce que fait chacun.

```bash
cd alaina-k8s/manifests

kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-configmap-nginx-conf.yaml
kubectl apply -f 02-configmap-site.yaml
kubectl apply -f 03-replicaset.yaml
kubectl apply -f 04-service.yaml
```

**Vérification à chaque étape :**
```bash
kubectl get ns alaina
kubectl get configmap -n alaina
kubectl get replicaset -n alaina
kubectl get pods -n alaina -o wide
kubectl get svc -n alaina
```
Tu dois voir 3 pods `alaina-web-xxxxx` en `Running` / `1/1 READY`. Si un pod
est en `CrashLoopBackOff` ou `Error` :
```bash
kubectl logs -n alaina <nom-du-pod>
kubectl describe pod -n alaina <nom-du-pod>
```
Les causes classiques : erreur de syntaxe dans le ConfigMap nginx (vérifie
les accolades), ou mauvais chemin de montage.

**Test rapide en local (avant même l'Ingress), avec port-forward :**
```bash
kubectl port-forward -n alaina svc/alaina-svc 8080:80
```
Ouvre `http://localhost:8080` dans un navigateur : le site alaina doit
s'afficher. Arrête ensuite avec `Ctrl+C`.

---

## PHASE 3 — Certificat TLS auto-signé + Ingress

```bash
cd alaina-k8s
chmod +x scripts/*.sh
./scripts/01-generate-tls-cert.sh
```
Ce script génère une paire clé/certificat auto-signée pour `alaina.local`
avec `openssl`, puis écrit `manifests/06-tls-secret.yaml` (base64 des deux
fichiers), prêt à être versionné.

```bash
kubectl apply -f manifests/06-tls-secret.yaml
kubectl apply -f manifests/05-ingress.yaml
```

**Vérification :**
```bash
kubectl get secret -n alaina alaina-tls-secret
kubectl get ingress -n alaina
kubectl describe ingress -n alaina alaina-ingress
```
La colonne `ADDRESS` de l'Ingress doit finir par se remplir avec l'IP de
Minikube (peut prendre quelques dizaines de secondes).

### Ajouter le nom de domaine local

```bash
minikube ip     # note l'IP affichée
./scripts/02-add-hosts-entry.sh
cat /etc/hosts | grep alaina.local
```

> Avec le driver **docker** sur Linux, `minikube ip` fonctionne en général
> directement pour l'Ingress. Si le site ne répond pas ensuite, lance en
> parallèle, dans un terminal dédié :
> ```bash
> minikube tunnel
> ```
> et remplace alors l'IP dans `/etc/hosts` par `127.0.0.1`.

**Test final HTTPS :**
```bash
curl -k https://alaina.local
```
(`-k` = ignore l'avertissement de certificat auto-signé). Tu dois recevoir le
HTML du site. Dans un navigateur, `https://alaina.local` affichera un
avertissement de sécurité (normal, certificat auto-signé) — clique sur
« Avancé » puis « Continuer » pour voir le site.

---

## PHASE 4 — Versionner sur GitHub

```bash
cd alaina-k8s
git init
git add .
git commit -m "Déploiement initial alaina : ReplicaSet + Service + Ingress + TLS"
git branch -M main
git remote add origin https://github.com/<TON-USER>/<TON-DEPOT>.git
git push -u origin main
```

> ⚠️ Le fichier `06-tls-secret.yaml` contient une clé privée encodée en
> base64 (donc lisible par quiconque a accès au dépôt). Pour ce projet
> pédagogique local, c'est acceptable si le dépôt est **privé**. Dans un
> contexte réel, on ne ferait jamais ça (voir la note dans le fichier
> `06-tls-secret.yaml.template`).

---

## PHASE 5 — Installer ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Vérification (peut prendre 2-3 minutes) :**
```bash
kubectl get pods -n argocd
```
Attends que tous les pods (`argocd-server`, `argocd-repo-server`,
`argocd-application-controller`, `argocd-redis`, `argocd-dex-server`) soient
`Running`.

### Accéder à l'interface ArgoCD

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443
```
Ouvre `https://localhost:8081` (avertissement TLS normal, c'est le certif
interne d'ArgoCD).

Récupère le mot de passe admin initial :
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```
Login : `admin` / le mot de passe affiché.

(Optionnel mais pratique) installe la CLI ArgoCD :
```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
```

---

## PHASE 6 — Créer l'Application ArgoCD (GitOps)

Édite `argocd/application.yaml` et remplace `repoURL` par l'URL réelle de
ton dépôt GitHub.

```bash
kubectl apply -f argocd/application.yaml
```

**Vérification :**
```bash
kubectl get application -n argocd
kubectl describe application alaina-site -n argocd
```
Statut attendu : `Sync Status: Synced` et `Health Status: Healthy` (dans
l'UI ArgoCD, tu verras le diagramme des ressources avec des coches vertes).

> Comme les manifests sont **déjà appliqués manuellement** en Phase 2/3,
> ArgoCD va simplement les reconnaître comme conformes à Git ("adopter" les
> ressources existantes puisqu'elles ont les mêmes noms/labels). Si tu pars
> de zéro, tu peux sauter tout `kubectl apply` manuel et laisser uniquement
> ArgoCD créer les ressources après le `git push`.

### Tester le GitOps de bout en bout

1. Modifie un texte dans `site/index.html`, régénère le ConfigMap (relance
   le petit script Python de génération, ou édite directement
   `manifests/02-configmap-site.yaml`).
2. `git add . && git commit -m "test gitops" && git push`.
3. Regarde l'UI ArgoCD (ou `kubectl get application -n argocd -w`) : la
   synchronisation se déclenche automatiquement en quelques secondes (le
   polling par défaut est de 3 min, ou instantané si tu configures un
   webhook GitHub → ArgoCD) et le nouveau contenu apparaît dans les pods.
4. Teste le **self-heal** : fais `kubectl scale replicaset alaina-web -n
   alaina --replicas=1` à la main. ArgoCD doit automatiquement remettre 3
   replicas en quelques secondes, car ça ne correspond plus à Git.

---

## Dépannage général

| Symptôme | Cause probable | Commande de diagnostic |
|---|---|---|
| `minikube start` échoue | Docker pas démarré / permissions | `sudo systemctl status docker`, `docker ps` |
| Pod `Pending` | Ressources insuffisantes | `kubectl describe pod -n alaina <pod>` |
| Pod `CrashLoopBackOff` | Erreur config nginx | `kubectl logs -n alaina <pod>` |
| Ingress sans `ADDRESS` | Addon ingress pas prêt | `kubectl get pods -n ingress-nginx` |
| `curl` timeout sur alaina.local | `/etc/hosts` ou tunnel manquant | `minikube ip`, `minikube tunnel` |
| ArgoCD `OutOfSync` en boucle | `syncPolicy.automated` mal formé, ou diff réel avec Git | `argocd app diff alaina-site` |
| ArgoCD `Unknown`/erreur repo | Mauvaise URL ou dépôt privé sans credentials | `kubectl logs -n argocd deploy/argocd-repo-server` |

---

## Nettoyage

```bash
kubectl delete -f argocd/application.yaml
kubectl delete namespace alaina
kubectl delete namespace argocd
minikube stop
minikube delete   # si tu veux repartir de zéro
```
