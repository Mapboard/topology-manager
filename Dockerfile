FROM node:14

RUN apt-get update \
  && apt-get install -y libpq-dev postgresql-client \
  && npm install -g npm@7 lerna \
  && npm cache clean -f \
  && npm cache verify

WORKDIR /app/

COPY ./packages/mapboard-server /app/packages/mapboard-server
COPY ./package.json ./lerna.json /app/
RUN npm --prefix packages/mapboard-server install
RUN npm install

COPY ./ /app/

EXPOSE 3006

ENTRYPOINT [ "/app/docker-assets/entry-script" ]
