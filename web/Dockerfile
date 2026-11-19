# ---- build stage ----
FROM node:20-alpine AS build
WORKDIR /app
ARG GIT_COMMIT=unknown
COPY package.json ./
RUN npm install
COPY . .
RUN echo "export const GIT_COMMIT = '${GIT_COMMIT}';" > src/version.js
RUN npm run build

# ---- final stage ----
FROM nginxinc/nginx-unprivileged:stable-alpine AS final
USER root
RUN apk upgrade --no-cache
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.revision=$GIT_COMMIT
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
USER nginx
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -q -O- http://127.0.0.1:8080/ || exit 1
EXPOSE 8080
