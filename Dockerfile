FROM node:8

RUN apt-get update \
 && apt-get install -y libpq-dev postgresql-client

RUN mkdir /app

WORKDIR /app

RUN npm install -g linklocal

COPY package.json /app/
COPY ./extensions/server/map-digitizer-server/package.json \
  /app/extensions/server/map-digitizer-server/package.json

RUN npm install

COPY *.* /app/

CMD /app/docker-assets/run
