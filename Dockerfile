FROM node:12

RUN apt-get update \
 && apt-get install -y libpq-dev postgresql-client \
 && npm install -g npm@7

RUN mkdir /app
WORKDIR /app/

COPY ./packages/ /app/packages/
COPY ./package.json /app/package.json

RUN npm install

COPY ./ /app/

CMD /app/docker-assets/run
