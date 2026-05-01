# --- Stage 1: Frontend Build ---
FROM node:25-alpine AS frontend-builder
WORKDIR /app/frontend

# Declare ARG so it can be passed during build
# Defaulting to / is best for SPA + PocketBase same-origin setups
ARG VITE_PB_URL=/
ENV VITE_PB_URL=$VITE_PB_URL

# Use legacy-peer-deps for Vite 8 compatibility as per project requirements
COPY frontend/package*.json ./
RUN npm install --legacy-peer-deps

COPY frontend/ .
RUN npm run build

# --- Stage 2: Backend Build ---
FROM golang:1.26-alpine AS backend-builder
# GCC is required for SQLite/CGO support in PocketBase
RUN apk add --no-cache gcc musl-dev
WORKDIR /app/backend

COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ .
# Reference: Move built Svelte assets to backend/pb_public[cite: 1, 2]
COPY --from=frontend-builder /app/frontend/build ./pb_public

# Compile binary using Makefile flags for optimization[cite: 1]
RUN go build -ldflags="-s -w" -o /app/backend/backend_bin .

# --- Stage 3: Final Image ---
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app

# Copy the compiled binary and static assets
COPY --from=backend-builder /app/backend/backend_bin ./backend_bin
COPY --from=backend-builder /app/backend/pb_public ./pb_public

# Copy and prepare the entrypoint script
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Create the data directory for Koyeb Persistent Volumes
RUN mkdir -p /app/pb_data
VOLUME /app/pb_data

# PocketBase default port[cite: 2]
EXPOSE 8090

ENTRYPOINT ["./entrypoint.sh"]
