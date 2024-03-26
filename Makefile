dev:
	bin/docker-develop

clean:
	docker-compose down --volumes

build:
	bin/docker-dist --no-push

test:
	poetry run pytest

dist:
	bin/docker-dist

.PHONY: dev clean build test dist
