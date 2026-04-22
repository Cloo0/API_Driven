# 🚀 API-Driven Infrastructure

> Orchestration de services AWS via **API Gateway** et **Lambda** dans un environnement émulé avec **LocalStack** et **GitHub Codespaces**.

Ce projet implémente une architecture *API-driven* dans laquelle de simples requêtes HTTP permettent de **démarrer, arrêter ou superviser** une instance EC2, sans jamais passer par une console graphique AWS. Tout est piloté par API, avec un endpoint REST dédié pour chaque action.

**⚡ Déploiement automatique** : un seul clic sur "Create codespace" suffit pour avoir toute l'infrastructure déployée et fonctionnelle en 3 minutes.

---

## 🎯 Objectif pédagogique

Comprendre comment des services cloud *serverless* (API Gateway + Lambda) peuvent **orchestrer dynamiquement** des ressources d'infrastructure (EC2). On apprend à :

- Émuler AWS localement avec LocalStack
- Développer et déployer une fonction Lambda
- Exposer cette Lambda derrière une API REST (API Gateway) avec plusieurs routes
- Piloter le tout uniquement via des appels HTTP
- Automatiser la reproductibilité d'un environnement cloud avec un devcontainer

---

## 🏗️ Architecture
                                     POST /ec2/start
┌─────────────┐         HTTP              POST /ec2/stop         ┌──────────┐     ┌─────────┐
│  Client     │ ────────────────────► ┌──────────────────┐ ────► │  Lambda  │ ──► │   EC2   │
│ (curl/Web)  │       POST /ec2/…     │   API Gateway    │       │ ec2-ctrl │     │ i-xxxx  │
└─────────────┘                       │      /dev        │       └──────────┘     └─────────┘
└──────────────────┘
│
│ route  →  action
│ /start →  start_instances
│ /stop  →  stop_instances
│ /status→  describe_instances
│
└─────── LocalStack (AWS émulé) ──────
│
GitHub Codespaces (port 4566)

---

## 🚀 Démarrage rapide (recommandé)

Tout est automatisé grâce à un **devcontainer** qui configure l'environnement au démarrage du Codespace.

### Prérequis

Un compte **LocalStack** gratuit ([app.localstack.cloud](https://app.localstack.cloud)) pour récupérer un token d'authentification.

### Étape 1 — Ajouter ton token LocalStack en secret Codespace

1. Va sur **https://github.com/settings/codespaces**
2. Clique **New secret**
3. **Name** : `LOCALSTACK_AUTH_TOKEN`
4. **Value** : ton token LocalStack
5. **Repository access** : sélectionne `API_Driven`
6. **Add secret**

### Étape 2 — Créer le Codespace

1. Sur la page du repo, clique **Code → Codespaces → Create codespace on main**
2. Attends 2-3 minutes pendant que le devcontainer s'installe

### Étape 3 — Rendre le port 4566 public

Dans le Codespace, onglet **PORTS** → clic droit sur **4566** → **Port Visibility** → **Public**.

⚠️ Cette étape manuelle est nécessaire car GitHub impose une confirmation explicite pour ouvrir un port à l'extérieur.

### ✅ C'est tout

Le script `setup.sh` a automatiquement :
- Installé LocalStack et AWS CLI
- Démarré LocalStack
- Créé une instance EC2
- Déployé la Lambda `ec2-controller`
- Créé l'API Gateway avec 3 routes

Les IDs générés (instance + API) et les URLs prêtes à l'emploi sont affichés dans le terminal et sauvegardés dans `~/.api-info.txt`.

```bash
cat ~/.api-info.txt
```

---

## 🎮 Utilisation de l'API

Toutes les routes utilisent la méthode **POST** avec un body JSON contenant `instance_id`.

| Action | Route | Description |
|--------|-------|-------------|
| ▶️ **Démarrer** | `POST /ec2/start` | Lance une instance EC2 arrêtée |
| ⏹️ **Arrêter** | `POST /ec2/stop` | Arrête une instance EC2 en marche |
| 🔍 **Status** | `POST /ec2/status` | Retourne l'état et les détails de l'instance |

### Format de l'URL

**Depuis le Codespace (local)** :
http://localhost:4566/restapis/<API_ID>/dev/user_request/ec2/<action>

**Depuis l'extérieur (URL publique)** :
https://[codespace]-4566.app.github.dev/restapis/<API_ID>/dev/user_request/ec2/<action>

### Body JSON

```json
{
  "instance_id": "i-xxxxxxxx"
}
```

### Exemples avec curl

```bash
# ▶️ DÉMARRER
curl -X POST \
  "https://<codespace>-4566.app.github.dev/restapis/<API_ID>/dev/_user_request_/ec2/start" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-xxxxxxxx"}'

# ⏹️ ARRÊTER
curl -X POST \
  "https://<codespace>-4566.app.github.dev/restapis/<API_ID>/dev/_user_request_/ec2/stop" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-xxxxxxxx"}'

# 🔍 STATUS
curl -X POST \
  "https://<codespace>-4566.app.github.dev/restapis/<API_ID>/dev/_user_request_/ec2/status" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-xxxxxxxx"}'
```

### Exemple de réponse (`start`)

```json
{
  "action": "start",
  "instance_id": "i-aa669a690a6ce1cdd",
  "result": {
    "StartingInstances": [{
      "InstanceId": "i-aa669a690a6ce1cdd",
      "CurrentState": { "Code": 0, "Name": "pending" },
      "PreviousState": { "Code": 80, "Name": "stopped" }
    }]
  }
}
```

### Utilisation via Postman / Insomnia

- **Method** : `POST`
- **URL** : une des trois routes
- **Headers** : `Content-Type: application/json`
- **Body** (raw JSON) : `{"instance_id":"i-xxxxxxxx"}`

---

## ✅ Vérification

### Lister les instances et leur état

```bash
awslocal ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

### Cycle de test complet

```bash
# 1. État initial
curl -s -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/status" \
  -H 'Content-Type: application/json' \
  -d "{\"instance_id\":\"$INSTANCE_ID\"}" | python3 -m json.tool

# 2. Stop
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/stop" \
  -H 'Content-Type: application/json' \
  -d "{\"instance_id\":\"$INSTANCE_ID\"}"

# 3. Start
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/start" \
  -H 'Content-Type: application/json' \
  -d "{\"instance_id\":\"$INSTANCE_ID\"}"
```

---

## 🛠️ Déploiement manuel (alternative)

Pour comprendre chaque étape plutôt qu'utiliser le devcontainer, voici les commandes manuelles.

<details>
<summary>Cliquer pour déplier le détail</summary>

### Installer LocalStack

```bash
python3 -m venv ~/rep_localstack
source ~/rep_localstack/bin/activate
pip install --upgrade pip localstack awscli awscli-local
localstack auth set-token VOTRE_TOKEN
localstack start -d
```

### Configurer AWS CLI

```bash
aws configure
# Access Key / Secret Key : test / test
# Region : us-east-1 | Format : json
```

### Créer l'instance EC2

```bash
awslocal ec2 create-key-pair --key-name demo-key
awslocal ec2 run-instances \
  --image-id ami-12345678 \
  --instance-type t2.micro \
  --key-name demo-key \
  --count 1
```

### Déployer la Lambda

```bash
zip function.zip lambda_function.py
awslocal lambda create-function \
  --function-name ec2-controller \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --zip-file fileb://function.zip
```

### Créer l'API Gateway avec 3 routes

```bash
API_ID=$(awslocal apigateway create-rest-api --name 'ec2-api' --query 'id' --output text)
ROOT_ID=$(awslocal apigateway get-resources --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' --output text)
EC2_RESOURCE_ID=$(awslocal apigateway create-resource \
  --rest-api-id $API_ID --parent-id $ROOT_ID \
  --path-part ec2 --query 'id' --output text)

for ACTION in start stop status; do
  RES=$(awslocal apigateway create-resource \
    --rest-api-id $API_ID --parent-id $EC2_RESOURCE_ID \
    --path-part $ACTION --query 'id' --output text)
  awslocal apigateway put-method --rest-api-id $API_ID --resource-id $RES \
    --http-method POST --authorization-type NONE
  awslocal apigateway put-integration --rest-api-id $API_ID --resource-id $RES \
    --http-method POST --type AWS_PROXY --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations
done

awslocal apigateway create-deployment --rest-api-id $API_ID --stage-name dev
```

</details>

---

## 📁 Structure du projet
.
├── .devcontainer/
│   ├── devcontainer.json     # Config Codespace (image, features, hooks)
│   └── setup.sh              # Script d'installation automatique
├── lambda_function.py        # Code de la fonction Lambda
├── README.md                 # Ce fichier
└── .gitignore

### Le fichier `devcontainer.json`

Configure l'environnement du Codespace :
- Image Python 3.11 Debian
- Feature `docker-in-docker` (LocalStack a besoin de Docker)
- Port 4566 forwardé
- Script `setup.sh` lancé après création
- Récupère le token LocalStack depuis le secret Codespace

### Le script `setup.sh`

Enchaîne automatiquement :
1. Installation LocalStack + AWS CLI
2. Configuration AWS CLI (credentials factices)
3. Authentification et démarrage LocalStack
4. Déploiement de la Lambda
5. Création EC2 + API Gateway

---

## 🧰 Dépannage

| Problème | Cause probable | Solution |
|---|---|---|
| `License activation failed` au démarrage | Token LocalStack absent | Vérifier le secret `LOCALSTACK_AUTH_TOKEN` dans https://github.com/settings/codespaces |
| `HTTP/2 401` + `www-authenticate: tunnel` en externe | Port 4566 non public | Onglet PORTS → clic droit → Port Visibility → Public |
| `Unknown options: --cli-binary-format` | AWS CLI v1 | Retirer l'option, non nécessaire en v1 |
| `502 Bad Gateway` | Lambda pas encore `Active` | Attendre quelques secondes, vérifier avec `awslocal lambda get-function` |
| Lambda `connection refused` | `localhost` utilisé au lieu de `LOCALSTACK_HOSTNAME` | Vérifier la construction de l'endpoint dans la Lambda |
| `InvalidInstanceID.NotFound` | LocalStack a redémarré | Recréer une instance avec `run-instances` |
| `Missing Authentication Token` | Route oubliée lors du déploiement | Relancer `create-deployment` après création des routes |
| Devcontainer échoue sur `docker-in-docker` | Moby incompatible Debian Trixie | `devcontainer.json` doit avoir `"moby": false` |
| Codespace `API_Driven` ne démarre pas | Codespace précédent crashé | Supprimer dans https://github.com/codespaces et recréer |

### Logs Lambda

```bash
awslocal logs tail /aws/lambda/ec2-controller --follow
```

### Mettre à jour le code Lambda

```bash
zip function.zip lambda_function.py
awslocal lambda update-function-code \
  --function-name ec2-controller \
  --zip-file fileb://function.zip
```

### Retrouver les IDs générés

```bash
cat ~/.api-info.txt
awslocal ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' --output table
awslocal apigateway get-rest-apis --query 'items[*].[id,name]' --output table
```

---

## 🔒 Sécurité

- Le token LocalStack **n'est jamais dans le repo** : il est stocké dans les Codespace Secrets GitHub (chiffrés côté serveur)
- Le `devcontainer.json` utilise `${localEnv:LOCALSTACK_AUTH_TOKEN}` pour injecter la valeur à l'exécution
- Chaque utilisateur du template doit fournir **son propre** token

---

## 🚀 Pour aller plus loin

- **Remplacer EC2 par Docker** : modifier la Lambda pour piloter des conteneurs Docker (via `docker-py`)
- **Ajouter une route `GET /ec2/list`** : lister toutes les instances
- **Sécuriser l'API** : passer en `AWS_IAM` ou utiliser des API keys
- **Gérer plusieurs instances** en batch
- **Ajouter un monitoring** DynamoDB pour l'historique des actions
- **Infrastructure as Code** : refaire le déploiement en Terraform ou AWS CDK

---

## 📚 Ressources

- [Documentation LocalStack](https://docs.localstack.cloud/)
- [AWS Lambda Python](https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html)
- [API Gateway — intégration Lambda proxy](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-create-api-as-simple-proxy-for-lambda.html)
- [GitHub Codespaces — Devcontainers](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/adding-a-dev-container-configuration/introduction-to-dev-containers)
- [awslocal (AWS CLI wrapper)](https://github.com/localstack/awscli-local)

---
