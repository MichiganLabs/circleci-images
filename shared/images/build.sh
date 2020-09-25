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

function run_goss_tests() {
    # make a copy of the Dockerfile in question, so we can modify the entrypoint, etc.
    GOSS_DOCKERFILE_PATH=~/circleci-bundles/$(echo ${DOCKERFILE_PATH} | sed 's|/Dockerfile|/goss|g')

    mkdir $GOSS_DOCKERFILE_PATH

    echo "----------------------------------------------------------------------------------------------------"
    echo "copying Dockerfile to $GOSS_DOCKERFILE_PATH for testing modifications..."
    cp ~/circleci-bundles/$DOCKERFILE_PATH $GOSS_DOCKERFILE_PATH

    # cat our additions onto the Dockerfile copy
    echo "----------------------------------------------------------------------------------------------------"
    echo "adding the following modifications to copied Dockerfile..."
    echo "----------------------------------------------------------------------------------------------------"
    cat ~/circleci-bundles/shared/goss/goss-add.Dockerfile
    cat ~/circleci-bundles/shared/goss/goss-add.Dockerfile >> $GOSS_DOCKERFILE_PATH/Dockerfile

    echo "----------------------------------------------------------------------------------------------------"
    echo "copying custom entrypoint for testing..."
    echo "----------------------------------------------------------------------------------------------------"
    cat ~/circleci-bundles/shared/goss/goss-entrypoint.sh
    cp ~/circleci-bundles/shared/goss/goss-entrypoint.sh $GOSS_DOCKERFILE_PATH

    # build our test image
    echo "----------------------------------------------------------------------------------------------------"
    echo "building modified test image: $IMAGE_NAME-goss..."
    echo "----------------------------------------------------------------------------------------------------"
    docker build -t $IMAGE_NAME-goss $GOSS_DOCKERFILE_PATH || (sleep 2; echo "retry building $IMAGE_NAME-goss"; docker build -t $IMAGE_NAME-goss $GOSS_DOCKERFILE_PATH)

    # run goss tests
    echo "----------------------------------------------------------------------------------------------------"
    echo "running goss tests on $IMAGE_NAME-goss..."
    echo "----------------------------------------------------------------------------------------------------"

    # run once with normal output, for stdout
    dgoss run $IMAGE_NAME-goss

    # save JUnit output to variable so we can control what we store
    export GOSS_OPTS="--format junit"
    results=$(dgoss run $IMAGE_NAME-goss)

    RESULTS_FILE=${IMAGE_NAME#*:}

    echo '<?xml version="1.0" encoding="UTF-8"?>' > \
      ~/circleci-bundles/test-results/$PLATFORM/$RESULTS_FILE.xml
    echo "${results#*<?xml version=\"1.0\" encoding=\"UTF-8\"?>}" | \
      sed "s|testsuite name=\"goss\"|testsuite name=\"$IMAGE_NAME\"|g" >> \
      ~/circleci-bundles/test-results/$PLATFORM/$RESULTS_FILE.xml

    echo "----------------------------------------------------------------------------------------------------"
    echo "removing goss variant..."
    echo "----------------------------------------------------------------------------------------------------"
    docker image rm $IMAGE_NAME-goss
    echo "----------------------------------------------------------------------------------------------------"
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

    run_goss_tests

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

    run_goss_tests

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
