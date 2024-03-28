dev:
	bin/docker-develop

clean:
	docker-compose down --volumes

build:
	bin/docker-dist --no-push

test:
	poetry run pytest -s

test-dev:
	poetry run pytest -s --no-drop -x --log-level=info

dist:
	bin/docker-dist

.PHONY: dev clean build test dist