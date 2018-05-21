#!/bin/bash

set -eu

NEW_ORG=${NEW_ORG:-michiganlabs}

DOCKERFILE_PATH=$1
pushd $(dirname $DOCKERFILE_PATH)

echo Building docker image from $DOCKERFILE_PATH

function repo_name() {
  repo_tag=$( echo ${DOCKERFILE_PATH} | sed 's|.*/\([^/]*\)/images/.*/Dockerfile|\1|g')
  echo "${NEW_ORG}/${repo_tag}"
}

REPO_NAME=$(repo_name)
IMAGE_NAME=${REPO_NAME}:$(cat TAG)


echo "OFFICIAL IMAGE REF: $IMAGE_NAME"

function is_variant() {
    echo ${DOCKERFILE_PATH} | grep -q -e 'images/.*/.*/Dockerfile'
}

function update_aliases() {
    for alias in $(cat ALIASES | sed 's/,/ /g')
    do
        echo handling alias ${alias}
        ALIAS_NAME=${REPO_NAME}:${alias}
        docker tag ${IMAGE_NAME} ${ALIAS_NAME}
        docker push ${ALIAS_NAME}
        docker image rm ${ALIAS_NAME}
    done
}

# pull to get cache and avoid recreating images unnecessarily
docker pull $IMAGE_NAME || true

if is_variant
then
    echo "image is a variant image"

    # retry building for transient failures; note docker cache kicks in
    # and this should only restart with the last failed step
    docker build -t $IMAGE_NAME . || (sleep 2; echo "retry building $IMAGE_NAME"; docker build -t $IMAGE_NAME .)

    docker push $IMAGE_NAME

    update_aliases

    # variants don't get reused, clean them up
    docker image rm $IMAGE_NAME
else
    # when building the new base image - always try to pull from latest
    # also keep new base images around for variants
    docker build --pull -t $IMAGE_NAME . || (sleep 2; echo "retry building $IMAGE_NAME"; docker build --pull -t $IMAGE_NAME .)
    docker push $IMAGE_NAME

    update_aliases
fi

popd
