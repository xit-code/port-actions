# syntax=docker/dockerfile:1
FROM maven:3.9-amazoncorretto-21-alpine

# Useful tools; no secrets are baked in the image
RUN apk add --no-cache bash git openssh-client curl jq python3

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
