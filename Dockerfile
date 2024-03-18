FROM node:18

# Install yarn berry

RUN apt-get update \
  && apt-get install -y libpq-dev postgresql-client \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app/

COPY package.json .yarnrc.yml yarn.lock /app/
COPY .yarn/releases /app/.yarn/releases

COPY ./packages/mapboard-server /app/packages/mapboard-server

RUN yarn install --frozen-lockfile

COPY ./ /app/

EXPOSE 3006

ENTRYPOINT [ "yarn", "exec", "/app/docker-assets/entry-script" ]
