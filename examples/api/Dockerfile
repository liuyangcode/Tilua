# Dockerfile for the Api example.
#
# Build from the REPOSITORY ROOT (docker-compose.yml sets context to ../..):
#
#   docker build -f examples/api/Dockerfile -t tilua-api .
#   docker run --rm -p 8081:8081 tilua-api
#
# No external services: the todo store is an in-memory worker singleton.

FROM openresty/openresty:1.21.4.1-buster

WORKDIR /app

COPY Tilua/ /app/Tilua/

COPY examples/api/nginx.conf /app/examples/api/nginx.conf
COPY examples/api/Api/       /app/examples/api/Api/

RUN mkdir -p /app/logs /app/examples/api/logs

EXPOSE 8081

CMD ["nginx", "-p", "/app", "-c", "examples/api/nginx.conf"]
