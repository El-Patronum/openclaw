SHELL := /bin/bash

.PHONY: rebuild verify clean-orphans

rebuild:
	OPENCLAW_SKIP_ONBOARD=1 ./docker-setup.sh
	docker compose up -d --force-recreate --remove-orphans openclaw-gateway
	./scripts/docker-verify.sh

verify:
	./scripts/docker-verify.sh

clean-orphans:
	docker compose down --remove-orphans
