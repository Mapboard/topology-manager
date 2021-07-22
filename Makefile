dev:
	bin/docker-develop

clean:
	docker-compose down --volumes

test:
	bin/docker-test

dist:
	bin/docker-dist

.PHONY: dev clean
