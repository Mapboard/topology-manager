FROM node:12

RUN apt-get update \
 && apt-get install -y libpq-dev postgresql-client
# && npm install -g npm@7

COPY ./packages/ /app/packages/

WORKDIR /app/packages/mapboard-server

RUN npm install
RUN npm run build

COPY ./package.json /app/package.json

WORKDIR /app/

RUN npm install

COPY ./ /app/

CMD /app/docker-assets/run
