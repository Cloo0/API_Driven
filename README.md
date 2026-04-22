# 🚀 API-Driven Infrastructure

> Orchestration de services AWS via **API Gateway** et **Lambda** dans un environnement émulé avec **LocalStack** et **GitHub Codespaces**.

Ce projet implémente une architecture *API-driven* dans laquelle de simples requêtes HTTP permettent de **démarrer, arrêter ou superviser** une instance EC2, sans jamais passer par une console graphique AWS. Tout est piloté par API, avec un endpoint REST dédié pour chaque action.

---

## 🎯 Objectif pédagogique

Comprendre comment des services cloud *serverless* (API Gateway + Lambda) peuvent **orchestrer dynamiquement** des ressources d'infrastructure (EC2). On apprend à :

- Émuler AWS localement avec LocalStack
- Développer et déployer une fonction Lambda
- Exposer cette Lambda derrière une API REST (API Gateway) avec plusieurs routes
- Piloter le tout uniquement via des appels HTTP

---

## 🏗️ Architecture

```
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
```

Le flux complet d'une requête :

1. Le client envoie une requête `POST` sur l'une des routes (`/ec2/start`, `/ec2/stop`, `/ec2/status`) avec un body JSON contenant l'`instance_id`
2. API Gateway reçoit la requête et invoque la Lambda en mode *proxy*
3. La Lambda lit l'**action dans le chemin de l'URL** puis appelle l'API EC2 via `boto3`
4. EC2 exécute l'action et retourne son état
5. La réponse JSON remonte jusqu'au client

---

## 📋 Prérequis

- Un compte **GitHub** avec accès à **Codespaces**
- Un compte **LocalStack** gratuit ([app.localstack.cloud](https://app.localstack.cloud)) pour récupérer un `AUTH_TOKEN`
- Connaissances de base en ligne de commande

---

## ⚙️ Installation

### Étape 1 — Créer le Codespace

1. Ouvrir le dépôt GitHub du projet
2. Cliquer sur **Code → Codespaces → Create codespace on main**
3. Attendre le démarrage du conteneur

### Étape 2 — Installer LocalStack

Dans le terminal du Codespace :

```bash
# Créer un environnement virtuel Python
python3 -m venv ~/rep_localstack
source ~/rep_localstack/bin/activate

# Installer LocalStack
pip install --upgrade pip
pip install localstack

# Authentifier LocalStack (remplacer par votre token)
localstack auth set-token VOTRE_TOKEN_LOCALSTACK

# Démarrer LocalStack en arrière-plan
localstack start -d

# Vérifier que ça tourne
localstack status services
```

💡 **Astuce** : pour un Codespace, stocker le token comme *GitHub Codespaces Secret* (`LOCALSTACK_AUTH_TOKEN`) évite de l'écrire en clair.

### Étape 3 — Installer les outils AWS CLI

```bash
pip install awscli awscli-local
aws configure
# AWS Access Key ID: test
# AWS Secret Access Key: test
# Default region: us-east-1
# Default output format: json
```

Le wrapper `awslocal` permet d'appeler l'AWS CLI directement sur LocalStack, sans avoir à préciser `--endpoint-url` à chaque commande.

### Étape 4 — Rendre le port 4566 public

Dans le Codespace :

1. Ouvrir l'onglet **PORTS**
2. Repérer le port **4566** (endpoint LocalStack)
3. Clic droit → **Port Visibility → Public**
4. Noter l'URL forwardée (format : `https://<codespace>-4566.app.github.dev`)

---

## 🧱 Déploiement de la solution

### 1. Créer l'instance EC2

```bash
awslocal ec2 create-key-pair --key-name demo-key

awslocal ec2 run-instances \
  --image-id ami-12345678 \
  --instance-type t2.micro \
  --key-name demo-key \
  --count 1
```

Récupérer l'`InstanceId` retourné (format `i-xxxxxxxx`) — il servira pour toutes les commandes suivantes.

### 2. Créer la fonction Lambda

Le fichier `lambda_function.py` contient le code de la Lambda. Elle lit l'**action dans le chemin** de l'URL (`/ec2/start`, `/ec2/stop`, `/ec2/status`) et appelle l'API EC2 correspondante via `boto3`.

```bash
# Zipper la fonction
zip function.zip lambda_function.py

# Déployer la Lambda
awslocal lambda create-function \
  --function-name ec2-controller \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --zip-file fileb://function.zip

# Attendre que la fonction soit active
awslocal lambda get-function \
  --function-name ec2-controller \
  --query 'Configuration.State' --output text
```

⚠️ **Point clé** : la Lambda tourne dans son propre conteneur Docker. Pour qu'elle puisse atteindre LocalStack, on utilise la variable d'environnement `LOCALSTACK_HOSTNAME` (injectée automatiquement par LocalStack) au lieu de `localhost`.

### 3. Créer l'API Gateway avec 3 routes

On crée une API REST avec une ressource `/ec2` parente et trois sous-ressources : `/start`, `/stop`, `/status`.

```bash
# 1. Créer l'API
API_ID=$(awslocal apigateway create-rest-api --name 'ec2-api' --query 'id' --output text)

# 2. Récupérer la ressource racine "/"
ROOT_ID=$(awslocal apigateway get-resources --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' --output text)

# 3. Créer la ressource /ec2 (parent commun)
EC2_RESOURCE_ID=$(awslocal apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part ec2 \
  --query 'id' --output text)

# 4. Fonction qui crée une sous-ressource + méthode POST + intégration Lambda
create_action() {
  local ACTION=$1
  local RES_ID=$(awslocal apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $EC2_RESOURCE_ID \
    --path-part $ACTION \
    --query 'id' --output text)

  awslocal apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RES_ID \
    --http-method POST \
    --authorization-type NONE > /dev/null

  awslocal apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RES_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations > /dev/null

  echo "  ✓ /ec2/$ACTION créé"
}

# 5. Créer les 3 routes
create_action start
create_action stop
create_action status

# 6. Déployer sur le stage "dev"
awslocal apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name dev

echo "API déployée — API_ID = $API_ID"
```

---

## 🎮 Utilisation de l'API

### Routes disponibles

Toutes les routes acceptent une méthode **POST** avec le header `Content-Type: application/json` et un body JSON contenant l'`instance_id`.

| Action | Route | Description |
|--------|-------|-------------|
| ▶️ **Démarrer** | `POST /ec2/start` | Lance une instance EC2 arrêtée |
| ⏹️ **Arrêter** | `POST /ec2/stop` | Arrête une instance EC2 en marche |
| 🔍 **Status** | `POST /ec2/status` | Retourne l'état et les détails de l'instance |

### Format de l'URL

**En local depuis le Codespace** :
```
http://localhost:4566/restapis/<API_ID>/dev/_user_request_/ec2/<action>
```

**Depuis l'extérieur (URL publique)** :
```
https://<codespace>-4566.app.github.dev/restapis/<API_ID>/dev/_user_request_/ec2/<action>
```

### Body JSON (identique pour les 3 actions)

```json
{
  "instance_id": "i-xxxxxxxx"
}
```

### Exemples d'utilisation avec curl

#### ▶️ Démarrer une instance

```bash
curl -X POST \
  "https://<codespace>-4566.app.github.dev/restapis/<API_ID>/dev/_user_request_/ec2/start" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-77aa6b6abec2187ab"}'
```

#### ⏹️ Arrêter une instance

```bash
curl -X POST \
  "https://<codespace>-4566.app.github.dev/restapis/<API_ID>/dev/_user_request_/ec2/stop" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-77aa6b6abec2187ab"}'
```

#### 🔍 Consulter l'état d'une instance

```bash
curl -X POST \
  "https://<codespace>-4566.app.github.dev/restapis/<API_ID>/dev/_user_request_/ec2/status" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-77aa6b6abec2187ab"}'
```

### Exemple de réponse (action `start`)

```json
{
  "action": "start",
  "instance_id": "i-77aa6b6abec2187ab",
  "result": {
    "StartingInstances": [
      {
        "InstanceId": "i-77aa6b6abec2187ab",
        "CurrentState": { "Code": 0, "Name": "pending" },
        "PreviousState": { "Code": 80, "Name": "stopped" }
      }
    ]
  }
}
```

### Utilisation via Postman / Insomnia

- **Méthode** : `POST`
- **URL** : une des trois routes ci-dessus
- **Headers** : `Content-Type: application/json`
- **Body** (raw JSON) : `{"instance_id":"i-xxxxxxxx"}`

---

## ✅ Vérification du fonctionnement

### Vérifier l'état d'une instance en CLI

```bash
awslocal ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

### Cycle de test complet

```bash
# 1. Instance en marche ?
curl -s -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/status" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-xxxx"}' | python3 -m json.tool

# 2. On l'arrête
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/stop" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-xxxx"}'

# 3. On la redémarre
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/start" \
  -H 'Content-Type: application/json' \
  -d '{"instance_id":"i-xxxx"}'
```

---

## 🧰 Dépannage

| Problème | Cause probable | Solution |
|---|---|---|
| `License activation failed` au démarrage de LocalStack | Token LocalStack absent | `localstack auth set-token <token>` |
| `Unknown options: --cli-binary-format` | AWS CLI v1 (vs v2) | Retirer l'option, non nécessaire en v1 |
| `502 Bad Gateway` sur l'appel curl | Lambda pas encore `Active` | `awslocal lambda get-function --function-name ec2-controller --query 'Configuration.State'` |
| Lambda renvoie `connection refused` | `localhost` utilisé au lieu de `LOCALSTACK_HOSTNAME` | Vérifier la construction de l'endpoint dans la Lambda |
| Page de login GitHub sur l'URL publique | Port non entièrement public | Onglet PORTS → clic droit sur 4566 → Port Visibility → Public |
| `InvalidInstanceID.NotFound` | LocalStack a été redémarré | Recréer une instance avec `run-instances` |
| Route `/ec2/start` renvoie `Missing Authentication Token` | Route oubliée lors du déploiement | Relancer `create-deployment` après avoir créé les routes |

### Consulter les logs de la Lambda

```bash
awslocal logs tail /aws/lambda/ec2-controller --follow
```

### Mettre à jour le code de la Lambda après modification

```bash
zip function.zip lambda_function.py
awslocal lambda update-function-code \
  --function-name ec2-controller \
  --zip-file fileb://function.zip
```

---

## 📁 Structure du projet

```
.
├── README.md                  # Ce fichier
├── lambda_function.py         # Code de la fonction Lambda
├── function.zip               # Archive pour déploiement Lambda
└── setup.sh                   # (optionnel) Script d'installation automatisé
```

---

## 🚀 Pour aller plus loin

- **Remplacer EC2 par Docker** : modifier la Lambda pour piloter des conteneurs Docker (via la lib `docker-py`) au lieu d'instances EC2 — plus réaliste car Docker tourne vraiment.
- **Ajouter une route `GET /ec2/list`** : lister toutes les instances et leur état.
- **Sécuriser l'API** : passer en `AWS_IAM` ou utiliser des API keys (`x-api-key`).
- **Gérer plusieurs instances** : accepter une liste `instance_ids` pour agir en batch.
- **Ajouter un monitoring** : stocker l'historique des actions dans une table DynamoDB.
- **Infrastructure as Code** : refaire tout ça avec Terraform ou AWS CDK pour automatiser le déploiement.

---

## 📚 Ressources utiles

- [Documentation LocalStack](https://docs.localstack.cloud/)
- [AWS Lambda avec Python](https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html)
- [API Gateway — intégration Lambda proxy](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-create-api-as-simple-proxy-for-lambda.html)
- [awslocal (AWS CLI wrapper)](https://github.com/localstack/awscli-local)

---

## 📝 Auteur

Atelier réalisé dans le cadre du TD **API-Driven Infrastructure**.
