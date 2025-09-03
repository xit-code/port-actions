# syntax=docker/dockerfile:1
FROM maven:3.9-amazoncorretto-21-alpine

# Optional but handy tools
RUN apk add --no-cache git bash openssh-client

# Improve cache: /github/home is mapped by GH Actions to the host
ENV MAVEN_CONFIG=/github/home/.m2

WORKDIR /github/workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
