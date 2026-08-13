#!/bin/bash

set -e

BUCKET="proudpops-demo-sitebucket"

echo "Uploading site..."

aws s3 sync public-site/ \
s3://$BUCKET \
--delete

echo
echo "Deployment complete."
