dev:
	bin/docker-develop

clean:
	docker-compose down --volumes

test:
	bin/docker-test

.PHONY: dev clean
