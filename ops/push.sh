#!/usr/bin/env bash

set -xeo pipefail
[[ -f "aws-envs.sh" ]] && source aws-envs.sh

BACKEND_IMAGE_NAME="boilerplate_api"
IMAGE_TAG=${CIRCLE_TAG:-${CIRCLE_BRANCH//\//-}}
CURRENT_BRANCH=${CIRCLE_TAG:-$CIRCLE_BRANCH}
BASE_TAG=latest
#Docker Image Version
# php 7.3, nginx 1.17.4
PHP_TAG=phpdockerio/php73-fpm:latest
HTTPD_TAG=nginx:1.17.4-alpine
# Wokdir
WORK_DIR=/var/www/
# Image names for docker
BASE_IMAGE_NAME=boilerplate/proxy-php-base

if [[ "$AWS_ENV" == "dev" ]]; then
    BACKEND_ECR_URL="${AWS_ACCOUNT_ID_DEV}.dkr.ecr.us-west-2.amazonaws.com/${AWS_ENV}-dev-duc-repository"
    AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID_DEV}"
    AWS_REGION="us-west-2"
    elif [[ "$AWS_ENV" == "stg" ]]; then
    BACKEND_ECR_URL="${AWS_ACCOUNT_ID_STG}.dkr.ecr.us-west-2.amazonaws.com/${AWS_ENV}-dev-duc-repository"
    AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID_STG}"
    AWS_REGION="us-west-2"
    elif [[ "$AWS_ENV" == "prd" ]]; then
    BACKEND_ECR_URL="${AWS_ACCOUNT_ID_PRD}.dkr.ecr.us-west-2.amazonaws.com/${AWS_ENV}-dev-duc-repository"
    AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID_PRD}"
    AWS_REGION="us-west-2"
fi

load_image(){
    docker image load -i "$BACKEND_IMAGE_NAME" &
    web_process=$! && echo $web_process
    wait $web_process
}

push_image() {
    $(aws ecr get-login --no-include-email --region $AWS_REGION --profile boilerplate-$AWS_ENV)
    docker image tag "${BACKEND_IMAGE_NAME}:latest" "${BACKEND_ECR_URL}:${image_tag}"
    docker image push "${BACKEND_ECR_URL}:${image_tag}" &
    web_process=$! && echo $web_process
    wait $web_process
}

build_image(){
    # Build Base image
    docker build --rm -f environments/Base.Dockerfile --build-arg WORK_DIR="${WORK_DIR}" --build-arg PHP_TAG="${PHP_TAG}"  --build-arg HTTPD_TAG="${HTTPD_TAG}" -t "${BASE_IMAGE_NAME}:${BASE_TAG}" .
    # Build App image
    docker build --rm -f "environments/Dockerfile" --build-arg IMAGE_NAME="${BASE_IMAGE_NAME}" --build-arg PORT=80 --build-arg BASE_TAG="${BASE_TAG}" -t "${BACKEND_IMAGE_NAME}:latest" .
}
save_image() {
    docker image save -o "$BACKEND_IMAGE_NAME" "${BACKEND_IMAGE_NAME}:latest" &
    web_process=$! && echo $web_process
    wait $web_process
}

if [[ "$AWS_ENV" == "dev" ]]; then
    build_image
    image_tag="$IMAGE_TAG-$(git rev-parse --short "$CURRENT_BRANCH")"
    push_image
    touch $BACKEND_IMAGE_NAME
    elif [[ "$AWS_ENV" == "stg" ]]; then
    build_image
    image_tag="$IMAGE_TAG-$(git rev-parse --short "$CURRENT_BRANCH")"
    push_image &
    push_process=$! && echo $push_process
    save_image
    wait $push_process
    elif [[ "$AWS_ENV" == "prd" ]]; then
    #build_image
    load_image
    image_tag="$IMAGE_TAG-$(git rev-parse --short "$CURRENT_BRANCH")"
    push_image
fi

cat <<EOT >> "aws-envs.sh"
export DOCKER_IMAGE="${ECR_URL}:${image_tag}"
export IMAGE_TAG="${image_tag}"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BACKEND_ECR_URL="$BACKEND_ECR_URL"
export AWS_REGION="$AWS_REGION"
export BACKEND_IMAGE_NAME="$BACKEND_IMAGE_NAME"
EOT

# TODO: prevent the following error
# The specified paths did not match any files
# [[ -f "$IMAGE_NAME" ]] || touch "$IMAGE_NAME"

#Test remove after done
cat aws-envs.sh
docker images
ls -la