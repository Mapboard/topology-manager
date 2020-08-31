FROM node:8

RUN apt-get update \
 && apt-get install -y libpq-dev postgresql-client

RUN mkdir /app

COPY ./ /app/

WORKDIR /app/
RUN npm install -g linklocal && linklocal && npm install
CMD /app/docker-assets/run
