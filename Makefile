.PHONY: up down build logs test web dev

up:
	docker compose up -d

down:
	docker compose down

build:
	docker compose -f docker-compose.build.yml build

logs:
	docker compose logs -f shengce

test:
	python3 -m pytest -q

web:
	cd web && npm run dev

dev:
	@echo "Run these in two terminals:"
	@echo "  DATA_DIR=./data ADMIN_PASSWORD=dev-pass ASR_ENGINE=fake uvicorn app.main:create_app --factory --reload --port 8000"
	@echo "  cd web && npm run dev"
