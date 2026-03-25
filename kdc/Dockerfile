# syntax=docker/dockerfile:1
# ============================================================
# MIT Kerberos KDC
# Provides authentication services for the Hadoop/Hive/Spark
# cluster in a Docker test environment.
# ============================================================
FROM debian:bookworm-slim

LABEL description="MIT Kerberos KDC for spark-hive-dock"

RUN apt-get update && apt-get install -y --no-install-recommends \
    krb5-kdc \
    krb5-admin-server \
    krb5-user \
    && rm -rf /var/lib/apt/lists/*

# Kerberos client config
COPY krb5.conf /etc/krb5.conf

# KDC initialization and startup script
COPY init-kdc.sh /init-kdc.sh
RUN chmod +x /init-kdc.sh

# KDC port (88) + admin port (749)
EXPOSE 88 749

ENTRYPOINT ["/init-kdc.sh"]
