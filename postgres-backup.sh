#!/bin/bash

: ${BACKUP_KEEP:=10}
: ${BUCKET_PREFIX:=default}

TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S")

LOG() {
	echo "${0##*/}: $1"
}

DIE() {
	LOG "ERROR: $1"
	exit ${2:-1}
}

######################################################################
##
## CHECK FOR REQUIRED VARIABLES
##

missing_vars=0
for var in POSTGRES_{DATABASE,HOST,PASSWORD,USER} AWS_{ACCESS_KEY_ID,SECRET_ACCESS_KEY} BUCKET_{HOST,PREFIX,NAME}; do
	if ! [[ "${!var}" ]]; then
		LOG "missing required variable $var"
		missing_vars=1
	fi
done

(( missing_vars == 1 )) && DIE "missing one or more required variables"

exit

######################################################################
##
## MAP IMAGE VARIABLES TO PG VARIABLES
##

# This translates the environment variables used by the postgres
# container image into the names expected by psql.
export PGDATABASE=$POSTGRES_DATABASE
export PGHOST=$POSTGRES_HOST
export PGPASSWORD=$POSTGRES_PASSWORD
export PGUSER=$POSTGRES_USER

# Create an mc alias named "BACKUP"
: ${MC_HOST_BACKUP:=https://${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}@$BUCKET_HOST}
export MC_HOST_BACKUP

dumpfile="backup-${TIMESTAMP}.tar"
target="BACKUP/${BUCKET_NAME}/${BUCKET_PREFIX}"

######################################################################
##
## PERFORM BACKUP
##

set -e

tmpdir=$(mktemp -d pgdumpXXXXXX)

LOG "back up postgres://${PGUSER}@${PGHOST}/${PGDATABASE}"

trap "rm -rf $tmpdir" EXIT
pg_dump -f "${tmpdir}/${dumpfile}" -F t

######################################################################
##
## SYNC TO S3 BUCKET
##

LOG "copy backup to ${BUCKET_HOST}:${target}/${dumpfile}"
mc -C $tmpdir/config cp "${tmpdir}/${dumpfile}" "${target}/${dumpfile}"

######################################################################
##
## EXPIRE OLDER BACKUPS
##

LOG "Cleaning up; keeping last $BACKUP_KEEP backups"
mc -C ${tmpdir}/config ls "${target}" --json |
	jq -r .key |
	sort |
	head -n-10 |
	xargs -r -I KEY mc -C ${tmpdir}/config rm "${target}/KEY"

LOG "All done"
