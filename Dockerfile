# ---- build stage ----#
FROM node:22-bookworm-slim AS build
WORKDIR /app

ENV HUSKY=0
ENV CI=true

RUN corepack enable && corepack prepare pnpm@9.15.9 --activate

RUN apt-get update && apt-get install -y --no-install-recommends git \
  && rm -rf /var/lib/apt/lists/*

ARG VITE_PUBLIC_APP_URL
ENV VITE_PUBLIC_APP_URL=${VITE_PUBLIC_APP_URL}

COPY package.json pnpm-lock.yaml* ./
RUN pnpm fetch

COPY . .
RUN pnpm install --offline --frozen-lockfile

RUN NODE_OPTIONS=--max-old-space-size=4096 pnpm run build

# ---- development stage (если нужен локально) ----
FROM build AS development
ARG VITE_LOG_LEVEL=debug
ARG DEFAULT_NUM_CTX
ENV VITE_LOG_LEVEL=${VITE_LOG_LEVEL} \
    DEFAULT_NUM_CTX=${DEFAULT_NUM_CTX} \
    RUNNING_IN_DOCKER=true
RUN mkdir -p /app/run
CMD ["pnpm", "run", "dev", "--host"]

# ---- production stage (должен быть ПОСЛЕДНИМ) ----
FROM build AS bolt-ai-production
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=5173
ENV HOST=0.0.0.0

ARG VITE_LOG_LEVEL=debug
ARG DEFAULT_NUM_CTX

ENV WRANGLER_SEND_METRICS=false \
    VITE_LOG_LEVEL=${VITE_LOG_LEVEL} \
    DEFAULT_NUM_CTX=${DEFAULT_NUM_CTX} \
    RUNNING_IN_DOCKER=true

RUN apt-get update && apt-get install -y --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*

# Копируем из build, где всё есть (и devDeps тоже, wrangler на месте)
COPY --from=build /app/build /app/build
COPY --from=build /app/node_modules /app/node_modules
COPY --from=build /app/package.json /app/package.json
COPY --from=build /app/bindings.sh /app/bindings.sh

RUN mkdir -p /root/.config/.wrangler && \
    echo '{"enabled":false}' > /root/.config/.wrangler/metrics.json

RUN chmod +x /app/bindings.sh

EXPOSE 5173

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5173/health || curl -f http://localhost:5173/api/health || exit 1

CMD ["pnpm", "run", "dockerstart"]
