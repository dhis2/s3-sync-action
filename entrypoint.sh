#!/bin/sh

set -e

if [ -z "$AWS_S3_BUCKET" ]; then
  echo "AWS_S3_BUCKET is not set. Quitting."
  exit 1
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
  echo "AWS_ACCESS_KEY_ID is not set. Quitting."
  exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "AWS_SECRET_ACCESS_KEY is not set. Quitting."
  exit 1
fi

# Default to us-east-1 if AWS_REGION not set.
if [ -z "$AWS_REGION" ]; then
  AWS_REGION="us-east-1"
fi

# Override default AWS endpoint if user sets AWS_S3_ENDPOINT.
if [ -n "$AWS_S3_ENDPOINT" ]; then
  ENDPOINT_APPEND="--endpoint-url $AWS_S3_ENDPOINT"
fi

# Create a dedicated profile for this action to avoid conflicts
# with past/future actions.
# https://github.com/jakejarvis/s3-sync-action/issues/1
aws configure --profile s3-sync-action <<-EOF > /dev/null 2>&1
${AWS_ACCESS_KEY_ID}
${AWS_SECRET_ACCESS_KEY}
${AWS_REGION}
text
EOF

if [ -n "$SOURCE_DIR" ]; then
  # Sync using our dedicated profile and suppress verbose messages.
  # All other flags are optional via the `args:` directive.
  sh -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_BUCKET}/${DEST_DIR} \
                --profile s3-sync-action \
                --no-progress \
                ${ENDPOINT_APPEND} $*"

  # the following is a hack to gzip the search_index.json file for our docs site
  # check if the file search/search_index.json exists in the source directory
  if [ -f "$SOURCE_DIR/search/search_index.json" ]; then
    # gzip the search_index.json file and copy it to the destination directory without the .gz extension
    # and with the content-encoding header set to gzip
    sh -c "gzip -c $SOURCE_DIR/search/search_index.json | aws s3 cp - s3://${AWS_S3_BUCKET}/${DEST_DIR}search/search_index.json \
                  --profile s3-sync-action \
                  --no-progress \
                  ${ENDPOINT_APPEND} \
                  --content-encoding gzip \
                  --content-type application/json"
  fi


fi


if [ -n "$SOURCE_FILE" ]; then
  # Copy single file using our dedicated profile and suppress verbose messages.
  # All other flags are optional via the `args:` directive.
  sh -c "aws s3 cp ${SOURCE_FILE} s3://${AWS_S3_BUCKET}/${DEST_DIR}${SOURCE_FILE} \
                --profile s3-sync-action \
                --no-progress \
                ${ENDPOINT_APPEND} $*"
fi

# If a AWS_CF_DISTRIBUTION_ID was given, create an invalidation for it.
if [ -n "$AWS_CF_DISTRIBUTION_ID" ]; then
  sh -c "aws cloudfront create-invalidation --distribution-id ${AWS_CF_DISTRIBUTION_ID} --paths '/*' --profile s3-sync-action"
fi

# Clear out credentials after we're done.
# We need to re-run `aws configure` with bogus input instead of
# deleting ~/.aws in case there are other credentials living there.
# https://forums.aws.amazon.com/thread.jspa?threadID=148833
aws configure --profile s3-sync-action <<-EOF > /dev/null 2>&1
null
null
null
text
EOF
