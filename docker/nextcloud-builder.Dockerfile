# syntax=docker/dockerfile:1

ARG NEXTCLOUD_VERSION=28.0.3
FROM nextcloud:${NEXTCLOUD_VERSION}-apache

ARG BUILD_CONTEXT=colmena-devops/devops/apps/nextcloud/builder
ARG NEXTCLOUD_API_WRAPPER_PORT=5001
ARG APACHE_APP_PATH=/var/www/nc_api_wrapper

# Install OS dependencies required by the wrapper
RUN apt-get update -y && \
  apt-get install -y \
  sudo \
  python3 \
  python3-pip \
  python3-venv \
  libapache2-mod-wsgi-py3 && \
  rm -rf /var/lib/apt/lists/*

# Custom entrypoint script
COPY ${BUILD_CONTEXT}/entrypoint.sh /api_wrapper_entrypoint.sh
RUN chmod +x /api_wrapper_entrypoint.sh

# Custom occ script
COPY ${BUILD_CONTEXT}/occ.sh /colmena_occ.sh
RUN chmod +x /colmena_occ.sh

# Prepare Nextcloud hooks
RUN mkdir -p /docker-entrypoint-hooks.d/post-installation
COPY ${BUILD_CONTEXT}/hooks/post-installation /docker-entrypoint-hooks.d/post-installation

# Prepare API wrapper project directory
RUN mkdir -p ${APACHE_APP_PATH}
WORKDIR ${APACHE_APP_PATH}

# Copy and set up the API wrapper
COPY ${BUILD_CONTEXT}/api .
RUN python3 -m venv .venv && \
  chmod +x .venv/bin/activate && \
  chown -R www-data:www-data ${APACHE_APP_PATH} && \
  chmod -R 755 ${APACHE_APP_PATH} && \
  . .venv/bin/activate && \
  .venv/bin/pip3 install -U pip && \
  .venv/bin/pip3 install -r requirements/prod.txt

# Configure apache for the wrapper
RUN echo "Listen ${NEXTCLOUD_API_WRAPPER_PORT}" >> /etc/apache2/ports.conf
COPY ${BUILD_CONTEXT}/apache/api.conf /etc/apache2/sites-available/api.conf
ENV API_WRAPPER_APACHE_PORT=${NEXTCLOUD_API_WRAPPER_PORT}
ENV APP_PATH=${APACHE_APP_PATH}

ENTRYPOINT ["/api_wrapper_entrypoint.sh"]
CMD ["apache2-foreground"]
