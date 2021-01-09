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
    for alias in $(sed 's/,/ /g' ALIASES)
    do
        echo handling alias ${alias}

        if [[ "$CIRCLE_BRANCH" == "master" || "$CIRCLE_BRANCH" == "staging" ]]; then
          ALIAS_NAME=${REPO_NAME}:${alias}
        else
          # we need to push tags w/o the branch/commit otherwise our FROM statements will break, but let's also push the branch/commit tags for visibility (it's test, verbosity doesn't matter)
          ALIAS_NAME=${REPO_NAME}:${alias}
          ALIAS_NAME_BRANCH_COMMIT=${REPO_NAME}:${alias}-${CIRCLE_BRANCH}-${CIRCLE_SHA1:0:12}
        fi

        if [[ "$CIRCLE_BRANCH" == "master" || "$CIRCLE_BRANCH" == "staging" ]]; then
          docker tag ${IMAGE_NAME} ${ALIAS_NAME}
          docker push ${ALIAS_NAME}
          docker image rm ${ALIAS_NAME}
        else
          # because we're in a for loop, this var will be set from previous iterations, so grep for the current ALIAS_NAME (which gets reset on every iteration)
          if [[ $(echo $ALIAS_NAME_BRANCH_COMMIT | grep $ALIAS_NAME) ]]; then
            docker tag ${IMAGE_NAME} ${ALIAS_NAME}
            docker push ${ALIAS_NAME}
            docker image rm ${ALIAS_NAME}
            docker tag ${IMAGE_NAME} ${ALIAS_NAME_BRANCH_COMMIT}
            docker push ${ALIAS_NAME_BRANCH_COMMIT}
            docker image rm ${ALIAS_NAME_BRANCH_COMMIT}
          fi
        fi
    done
}

# pull to get cache and avoid recreating images unnecessarily
docker pull $IMAGE_NAME || true

# function to support new ccitest org, which will handle images created on any non-master/staging branches
# for these images, we want to know what branch (& commit) they came from, & since they are far from customer-facing, we don't care if the tags are annoyingly verbose
# however, we also need the regular tag, b/c images depend on them in their Dockerfile FROM statements
function handle_ccitest_org_images() {
    if [[ ! "$CIRCLE_BRANCH" == "master" && ! "$CIRCLE_BRANCH" == "staging" ]]; then
        IMAGE_NAME_BRANCH_COMMIT=${REPO_NAME}:$(cat TAG)-${CIRCLE_BRANCH}-${CIRCLE_SHA1:0:12}
        docker tag ${IMAGE_NAME} ${IMAGE_NAME_BRANCH_COMMIT}
        docker push $IMAGE_NAME_BRANCH_COMMIT
    fi
}

if is_variant
then
    echo "image is a variant image"

    # retry building for transient failures; note docker cache kicks in
    # and this should only restart with the last failed step
    docker build -t $IMAGE_NAME . || (sleep 2; echo "retry building $IMAGE_NAME"; docker build -t $IMAGE_NAME .)

    # provide an option to build but not push images
    # this can be used to build/test images on forked PRs
    # or just to skip pushing if desired

    if [[ $PUSH_IMAGES == true ]]; then
        docker push $IMAGE_NAME

        handle_ccitest_org_images

        update_aliases
    fi

    # variants don't get reused, clean them up
    docker image rm $IMAGE_NAME

    popd
else
    # when building the new base image - always try to pull from latest
    # also keep new base images around for variants
    docker build --pull -t $IMAGE_NAME . || (sleep 2; echo "retry building $IMAGE_NAME"; docker build --pull -t $IMAGE_NAME .)

    # provide an option to build but not push images
    # this can be used to build/test images on forked PRs
    # or just to skip pushing if desired

    if [[ $PUSH_IMAGES == true ]]; then
        docker push $IMAGE_NAME

        handle_ccitest_org_images

        update_aliases
    fi

    popd
fi
