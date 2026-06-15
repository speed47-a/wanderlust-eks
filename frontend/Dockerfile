# ============================================================
# Frontend Dockerfile - Production Version
# 
# Stage 1: Build the React app into static files
# Stage 2: Serve with nginx (tiny, fast, no Vite issues)
# ============================================================

# ── Stage 1: Build ───────────────────────────────────────────
FROM node:21 AS builder

WORKDIR /app

# Copy package files first (better Docker layer caching)
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of the app
COPY . .

# Build the React app into static files → outputs to /app/dist
# VITE_API_PATH gets baked into the build here
ARG VITE_API_PATH
ENV VITE_API_PATH=$VITE_API_PATH
RUN npm run build

# ── Stage 2: Serve with nginx ─────────────────────────────────
FROM nginx:alpine

# Copy built static files to nginx's serving directory
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy custom nginx config to handle React Router (client-side routing)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
