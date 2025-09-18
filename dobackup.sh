#!/usr/bin/env sh

set -e

source .env

# default storage class to standard if not provided
S3_STORAGE_CLASS=${S3_STORAGE_CLASS:-STANDARD}

# generate file name for tar
FILE_BASENAME="${BACKUP_NAME:-backup}-$(date "+%Y-%m-%d_%H-%M-%S").tar.gz"
TMP_FILE_NAME="/tmp/${FILE_BASENAME}"

# Check if TARGET variable is set
if [ -z "${TARGET}" ]; then
    echo "TARGET env var is not set so we use the default value (/data)"
    TARGET=/data
else
    echo "TARGET env var is set"
fi

echo "creating archive"
if [ "${IGNORE_FAILED_READ}" == "true" ]; then
  tar --ignore-failed-read -zcvf "${TMP_FILE_NAME}" "${TARGET}" 1>/dev/null
else
  tar -zcvf "${TMP_FILE_NAME}" "${TARGET}" 1>/dev/null
fi

# encrypt if passphrase provided
if [ -z "${GPG_PASSPHRASE}" ]; then
  FILE_NAME="${TMP_FILE_NAME}"
else
  echo "${GPG_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo "${GPG_CIPHER_ALGO:-AES256}" --output "${TMP_FILE_NAME}.enc" "${TMP_FILE_NAME}"
  rm "${TMP_FILE_NAME}"
  FILE_NAME="${TMP_FILE_NAME}.enc"
  FILE_BASENAME="${FILE_BASENAME}.enc"
fi

# backup local if enabled
if [ -n "${LOCAL_BACKUP_DIR}" ]; then
  echo "creating local backup at ${LOCAL_BACKUP_DIR}/${FILE_BASENAME}"
  cp "${FILE_NAME}" "${LOCAL_BACKUP_DIR}/${FILE_BASENAME}"
  echo "local backup succeeded"
fi

if [ -z "${S3_ENDPOINT}" ]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

echo "uploading archive to S3 [${FILE_NAME}, storage class - ${S3_STORAGE_CLASS}]"
aws s3 ${AWS_ARGS} cp --storage-class "${S3_STORAGE_CLASS}" "${FILE_NAME}" "${S3_BUCKET_URL}"
echo "removing local archive"
rm "${FILE_NAME}"
echo "done"

if [ -n "${WEBHOOK_URL}" ]; then
    echo "notifying webhook"
    curl -m 10 --retry 5 "${WEBHOOK_URL}"
fi
