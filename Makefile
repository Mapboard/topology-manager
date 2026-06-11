dev:
	bin/docker-develop

clean:
	docker-compose down --volumes

build:
	bin/docker-dist --no-push

test:
	uv run pytest

test-debug:
	uv run pytest -s --log-cli-level=info

test-dev:
	uv run pytest -s --no-drop -x --log-level=info

dist:
	bin/docker-dist

.PHONY: dev clean build test dist
