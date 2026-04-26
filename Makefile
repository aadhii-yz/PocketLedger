.PHONY: all build frontend backend clean dev

BINARY_NAME=backend
BUILD_FLAGS=-ldflags="-s -w"

## all: build everything (default)
all: build

## build: install deps, build frontend + backend, copy assets
build: frontend backend copy

## frontend: install deps and build Svelte
frontend:
	@echo ">>> Building frontend..."
	cd frontend && npm i && npm run build

## backend: tidy deps and compile Go binary
backend:
	@echo ">>> Building backend..."
	cd backend && go mod tidy && go build $(BUILD_FLAGS) -o $(BINARY_NAME) .

## copy: copy Svelte build output into pb_public
copy:
	@echo ">>> Copying frontend build to pb_public..."
	cp -r frontend/build backend/pb_public

## run: build everything then start the server
run: build
	@echo ">>> Starting server..."
	cd backend && ./$(BINARY_NAME) serve

## dev-frontend: start Svelte dev server
dev-frontend:
	cd frontend && npm run dev

## clean: remove build artifacts
clean:
	@echo ">>> Cleaning build artifacts..."
	rm -rf frontend/build
	rm -rf backend/pb_public
	rm -f backend/$(BINARY_NAME)

## help: list available targets
help:
	@grep -E '^##' Makefile | sed 's/## //'

