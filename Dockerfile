FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# No systemd in this container — deny package-postinst service auto-starts during build.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

# Base tooling + ttyd deps + postgres client (for restore/psql); Odoo's own deps come from its .deb.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget curl git python3 python3-pip \
        postgresql-client xz-utils neofetch tini \
    && rm -rf /var/lib/apt/lists/*

# ttyd web terminal (same binary as the upstream template).
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 \
    && chmod +x /bin/ttyd

# Fixed UID/GID so ownership on the persistent volume stays stable across rebuilds.
RUN groupadd -g 106 odoo \
    && useradd -u 103 -g 106 -d /var/lib/odoo -s /usr/sbin/nologin odoo

# Odoo 19 Enterprise: 283MB .deb fetched from R2; lxml-html-clean shim is committed in-repo
# (jammy ships lxml 4.8 with lxml.html.clean built in; the shim satisfies the deb's dependency).
COPY packages/python3-lxml-html-clean_1.0+jammy1_all.deb /tmp/lxml-shim.deb
RUN wget -qO /tmp/odoo.deb https://bucket.vu.ai/odoo/odoo_19_enterprise.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/lxml-shim.deb /tmp/odoo.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/odoo.deb /tmp/lxml-shim.deb

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8069 = Odoo (the port the odoo2.vu.studio domain forwards to). 8080 = ttyd web terminal.
EXPOSE 8069
EXPOSE 8080

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
