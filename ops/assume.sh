#!/bin/bash

set -xeuo pipefail
set -u

usage() {
  cat <<'EOT'
Usage: assume.sh [-p] [-h]
  -p     Approved deploy to production
  -h     Print this help
EOT
}

approved=false

while getopts ':p' args; do
    case "$args" in
        a)
            approved=true
        ;;
        h)
            usage
            exit 0
        ;;
        *)
            usage
            exit 1
        ;;
    esac
done
CURRENT_BRANCH=${CIRCLE_TAG:-$CIRCLE_BRANCH}

if [[ "${CURRENT_BRANCH}" =~ ^(develop|master|pre-release\/v1.0.0|v([0-9]+\.){2}[0-9]+)$ ]]; then
    if [[ "$approved" == true ]]; then
        aws_account_id="$AWS_ACCOUNT_ID_PRD"
        aws_env="prd"
        aws_iam_role_external_id="$AWS_IAM_ROLE_EXTERNAL_ID_PRD"
        aws_boilerplate_kms="$AWS_KMS_PRD"
    else
        aws_account_id="$AWS_ACCOUNT_ID_STG"
        aws_env="stg"
        aws_iam_role_external_id="$AWS_IAM_ROLE_EXTERNAL_ID_STG"
        aws_boilerplate_kms="$AWS_KMS_STG"
    fi
    elif [[ "${CURRENT_BRANCH}" =~ ^(feature\/sprint[0-9]+)$ ]]; then
    aws_account_id="$AWS_ACCOUNT_ID_DEV"
    aws_env="dev"
    aws_iam_role_external_id="$AWS_IAM_ROLE_EXTERNAL_ID_DEV"
    aws_boilerplate_kms="$AWS_KMS_DEV"
fi

aws_sts_credentials="$(aws sts assume-role \
    --role-arn "arn:aws:iam::${aws_account_id}:role/circleci-of-${aws_env}" \
    --role-session-name "$CIRCLE_USERNAME" \
    --external-id "$aws_iam_role_external_id" \
    --duration-seconds "1800" \
    --query "Credentials" \
--output "json")"

aws configure --profile boilerplate-${aws_env} << EOF
$(echo "$aws_sts_credentials" | jq -r '.AccessKeyId')
$(echo "$aws_sts_credentials" | jq -r '.SecretAccessKey')
us-west-2
json
EOF

echo aws_session_token="$(echo "$aws_sts_credentials" | jq -r '.SessionToken')" >> ~/.aws/credentials
echo aws_expiration="$(echo "$aws_sts_credentials" | jq -r '.Expiration')" >> ~/.aws/credentials

cat <<EOT > "aws-envs.sh"
export AWS_ACCESS_KEY_ID="$(echo "$aws_sts_credentials" | jq -r '.AccessKeyId')"
export AWS_SECRET_ACCESS_KEY="$(echo "$aws_sts_credentials" | jq -r '.SecretAccessKey')"
export AWS_SESSION_TOKEN="$(echo "$aws_sts_credentials" | jq -r '.SessionToken')"
export AWS_ACCOUNT_ID="$aws_account_id"
export AWS_DEFAULT_REGION="us-west-2"
export AWS_ENV="$aws_env"
export AWS_BOILERPLATE_KMS="$aws_boilerplate_kms"
EOT

source aws-envs.sh

ecs_cluster_name="${aws_env}-boilerplate-cluster-ecs"
backend_service_name="${aws_env}-boilerplate-service-backend-blue-ecs"

cat <<EOT >> "aws-envs.sh"
export ECS_CLUSTER_NAME="$ecs_cluster_name"
export BACKEND_SERVICE_NAME="$backend_service_name"
EOT

source aws-envs.sh

#####################
#GET FRONTEND ENV
#####################
ENV=${aws_env}
REGION=${AWS_DEFAULT_REGION}
PROFILE=boilerplate-${aws_env}
