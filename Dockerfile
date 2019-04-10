FROM node:8

RUN apt-get update \
 && apt-get install -y libpq-dev postgresql-client
