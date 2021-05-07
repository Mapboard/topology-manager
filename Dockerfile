FROM node:14

RUN apt-get update \
  && apt-get install -y libpq-dev postgresql-client \
  && npm install -g npm@7 \
  && npm cache clean -f \
  && npm cache verify

WORKDIR /app/

COPY ./packages/mapboard-server /app/packages/mapboard-server
COPY ./package.json ./lerna.json /app/
RUN npm install

COPY ./ /app/

CMD /app/docker-assets/run
