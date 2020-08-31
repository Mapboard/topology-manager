FROM node:8

RUN apt-get update \
 && apt-get install -y libpq-dev postgresql-client

RUN mkdir /app
WORKDIR /app/

COPY ./extensions/server/map-digitizer-server/ /app/extensions/server/map-digitizer-server/
COPY ./package.json /app/package.json

RUN npm install -g linklocal && linklocal && npm install

COPY ./ /app/

CMD /app/docker-assets/run
