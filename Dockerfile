FROM node:8

RUN apt-get update \
 && apt-get install -y libpq-dev postgresql-client

RUN mkdir /app

WORKDIR /app

RUN npm install -g linklocal && \
  mkdir -p /app/extensions/server/map-digitizer-server

COPY package.json /app/
COPY ./extensions/server/map-digitizer-server/*.* \
  /app/extensions/server/map-digitizer-server/

RUN linklocal && npm install

COPY . /app/

CMD /app/docker-assets/run
