#!/usr/bin/env bash
# Deploys/updates the notify-new-user Lambda + its public Function URL.
#
# Required environment variables (export these in your shell before running,
# never hardcode them here or commit them):
#   SMTP_USER          Gmail address used to send the notification
#   SMTP_APP_PASSWORD  Gmail App Password for SMTP_USER
#   DATABASE_URL       Firebase Realtime Database URL, e.g. https://notifierme-5ff4f-default-rtdb.firebaseio.com
#   NOTIFY_TO_EMAIL    Recipient of the pending-approval notification
# Optional:
#   AWS_REGION          (default: eu-west-1)
#   FUNCTION_NAME       (default: notify-new-user)

set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env.local ]; then
  set -a
  # shellcheck disable=SC1091
  source .env.local
  set +a
fi

: "${SMTP_USER:?Set SMTP_USER}"
: "${SMTP_APP_PASSWORD:?Set SMTP_APP_PASSWORD}"
: "${DATABASE_URL:?Set DATABASE_URL}"
: "${NOTIFY_TO_EMAIL:?Set NOTIFY_TO_EMAIL}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
FUNCTION_NAME="${FUNCTION_NAME:-notify-new-user}"
ROLE_NAME="${FUNCTION_NAME}-role"

echo "Installing dependencies..."
npm install --omit=dev --silent

echo "Zipping function..."
rm -f function.zip
zip -qr function.zip index.mjs package.json node_modules

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "Creating IAM role $ROLE_NAME..."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]
    }' >/dev/null
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  echo "Waiting for IAM role to propagate..."
  sleep 10
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
ENV_VARS="Variables={DATABASE_URL=${DATABASE_URL},SMTP_USER=${SMTP_USER},SMTP_APP_PASSWORD=${SMTP_APP_PASSWORD},NOTIFY_TO_EMAIL=${NOTIFY_TO_EMAIL}}"

if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Updating existing function code..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file fileb://function.zip \
    --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
  echo "Updating function configuration..."
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
else
  echo "Creating function..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime nodejs20.x \
    --role "$ROLE_ARN" \
    --handler index.handler \
    --zip-file fileb://function.zip \
    --timeout 15 \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
fi

if ! aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Creating Function URL..."
  aws lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --region "$AWS_REGION" >/dev/null
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id FunctionURLAllowPublicAccess \
    --action lambda:InvokeFunctionUrl \
    --principal "*" \
    --function-url-auth-type NONE \
    --region "$AWS_REGION" >/dev/null
  # Function URLs (as of Oct 2025) also require a separate lambda:InvokeFunction
  # grant scoped to invoked-via-function-url, or every call 403s.
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id UrlPolicyInvokeFunction \
    --action lambda:InvokeFunction \
    --principal "*" \
    --invoked-via-function-url \
    --region "$AWS_REGION" >/dev/null
fi

URL=$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query FunctionUrl --output text)
echo ""
echo "Deployed. Function URL:"
echo "$URL"
