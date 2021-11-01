FROM postgres:13-alpine
RUN apk add --update jq bash
COPY --from=quay.io/minio/mc /usr/bin/mc /usr/bin
COPY --chmod=0755 postgres-backup.sh /usr/local/bin/postgres-backup.sh
CMD /usr/local/bin/postgres-backup.sh
