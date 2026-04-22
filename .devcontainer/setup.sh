#!/usr/bin/env bash
set -e

echo "=========================================="
echo "  API-Driven Infrastructure - Setup"
echo "=========================================="

# --- 1. Installer LocalStack et AWS CLI ---
echo ""
echo "[1/5] Installation de LocalStack et AWS CLI..."
pip install --upgrade pip --quiet
pip install localstack awscli awscli-local --quiet

# --- 2. Configurer AWS CLI (credentials factices pour LocalStack) ---
echo "[2/5] Configuration AWS CLI..."
mkdir -p ~/.aws
cat > ~/.aws/credentials << AWSEOF
[default]
aws_access_key_id = test
aws_secret_access_key = test
AWSEOF
cat > ~/.aws/config << AWSEOF
[default]
region = us-east-1
output = json
AWSEOF

# --- 3. Authentifier et démarrer LocalStack ---
echo "[3/5] Démarrage de LocalStack..."
if [ -n "$LOCALSTACK_AUTH_TOKEN" ]; then
  localstack auth set-token "$LOCALSTACK_AUTH_TOKEN"
  echo "  ✓ Token LocalStack configuré"
else
  echo "  ⚠ LOCALSTACK_AUTH_TOKEN non défini — ajoute-le dans les Codespaces Secrets"
fi

localstack start -d

# Attendre que LocalStack soit prêt
echo "  Attente de la disponibilité de LocalStack..."
for i in {1..30}; do
  if curl -s http://localhost:4566/_localstack/health >/dev/null 2>&1; then
    echo "  ✓ LocalStack est prêt"
    break
  fi
  sleep 2
done

# --- 4. Déployer la Lambda ---
echo "[4/5] Déploiement de la Lambda ec2-controller..."
if [ -f lambda_function.py ]; then
  zip -q function.zip lambda_function.py
  awslocal lambda create-function \
    --function-name ec2-controller \
    --runtime python3.11 \
    --handler lambda_function.lambda_handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file fileb://function.zip > /dev/null
  echo "  ✓ Lambda déployée"

  # Attendre que la Lambda soit Active
  for i in {1..20}; do
    STATE=$(awslocal lambda get-function --function-name ec2-controller \
      --query 'Configuration.State' --output text 2>/dev/null || echo "Pending")
    if [ "$STATE" = "Active" ]; then break; fi
    sleep 2
  done
else
  echo "  ⚠ lambda_function.py introuvable, skip"
fi

# --- 5. Créer l'EC2 et l'API Gateway ---
echo "[5/5] Création des ressources AWS..."

# Key pair + EC2
awslocal ec2 create-key-pair --key-name demo-key > /dev/null 2>&1 || true
INSTANCE_ID=$(awslocal ec2 run-instances \
  --image-id ami-12345678 \
  --instance-type t2.micro \
  --key-name demo-key \
  --count 1 \
  --query 'Instances[0].InstanceId' --output text)
echo "  ✓ Instance EC2 créée : $INSTANCE_ID"

# API Gateway avec 3 routes
API_ID=$(awslocal apigateway create-rest-api --name 'ec2-api' --query 'id' --output text)
ROOT_ID=$(awslocal apigateway get-resources --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' --output text)
EC2_RES=$(awslocal apigateway create-resource \
  --rest-api-id $API_ID --parent-id $ROOT_ID \
  --path-part ec2 --query 'id' --output text)

for ACTION in start stop status; do
  RES=$(awslocal apigateway create-resource \
    --rest-api-id $API_ID --parent-id $EC2_RES \
    --path-part $ACTION --query 'id' --output text)
  awslocal apigateway put-method \
    --rest-api-id $API_ID --resource-id $RES \
    --http-method POST --authorization-type NONE > /dev/null
  awslocal apigateway put-integration \
    --rest-api-id $API_ID --resource-id $RES \
    --http-method POST --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations > /dev/null
done

awslocal apigateway create-deployment --rest-api-id $API_ID --stage-name dev > /dev/null
echo "  ✓ API Gateway déployée (API_ID = $API_ID)"

# --- Résumé ---
cat > ~/.api-info.txt << INFOEOF
=================================================================
  API-Driven Infrastructure - Déploiement terminé !
=================================================================

  Instance EC2 ID : $INSTANCE_ID
  API Gateway ID  : $API_ID

  URLs (local) :
    ▶️  POST http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/start
    ⏹️  POST http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/stop
    🔍  POST http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/status

  Body JSON : {"instance_id":"$INSTANCE_ID"}

  Exemple :
    curl -X POST \\
      "http://localhost:4566/restapis/$API_ID/dev/_user_request_/ec2/status" \\
      -H 'Content-Type: application/json' \\
      -d '{"instance_id":"$INSTANCE_ID"}'

=================================================================
INFOEOF

cat ~/.api-info.txt
echo ""
echo "ℹ️  Ce résumé est sauvegardé dans ~/.api-info.txt"
