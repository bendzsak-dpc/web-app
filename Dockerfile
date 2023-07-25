###############
### STAGE 1: Build app
###############
ARG BUILDER_IMAGE=node:19-alpine
ARG NGINX_IMAGE=nginx:1.19.3

FROM $BUILDER_IMAGE as builder
ARG NPM_REGISTRY_URL=https://registry.npmjs.org/
ARG BUILD_ENVIRONMENT_OPTIONS="--configuration production"
ARG PUPPETEER_DOWNLOAD_HOST_ARG=https://storage.googleapis.com
ARG PUPPETEER_CHROMIUM_REVISION_ARG=1011831

RUN apk add --no-cache git

WORKDIR /usr/src/app

ENV PATH /usr/src/app/node_modules/.bin:$PATH

# Export Puppeteer env variables for installation with non-default registry.
ENV PUPPETEER_DOWNLOAD_HOST $PUPPETEER_DOWNLOAD_HOST_ARG
ENV PUPPETEER_CHROMIUM_REVISION $PUPPETEER_CHROMIUM_REVISION_ARG

COPY ./ /usr/src/app/

RUN npm cache clear --force

RUN npm config set fetch-retry-maxtimeout 120000
RUN npm config set registry $NPM_REGISTRY_URL --location=global

RUN npm install --location=global @angular/cli@13.3.10

RUN npm install

RUN ng build --output-path=/dist $BUILD_ENVIRONMENT_OPTIONS

###############
### STAGE 2: Serve app with nginx ###
###############
FROM amazonlinux:2023

ARG CACHEBUST=1

RUN dnf -y upgrade && \
# Install nginx
    dnf -y install nginx && \
# Create the non-root user to run the application
    dnf -y install shadow-utils && \
    groupadd --system --gid 1000 nginxgroup && \
    useradd --uid 1000 --gid nginxgroup --no-user-group nginxuser && \
    dnf -y remove shadow-utils && \
# Install envsubst
    dnf -y install gettext && \
# Clean up the yum cache
    dnf -y clean all

RUN mkdir -p /app/logs
RUN rm -rf /var/log/nginx && ln -sf /app/logs /var/log/nginx
RUN chown -R nginxuser:nginxgroup /var/lib/nginx/
RUN chown -R nginxuser:nginxgroup /app

COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=builder --chown=nginxuser:nginxgroup /dist /app/html
EXPOSE 4200
USER nginxuser:nginxgroup

# When the container starts, replace the env.js with values from environment variables
CMD ["/bin/sh",  "-c",  "envsubst < /app/html/assets/env.template.js > /app/html/assets/env.js && exec nginx -g 'daemon off;'"]
