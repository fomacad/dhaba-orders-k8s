# ---- build stage ----
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
COPY . .
RUN go mod tidy && go mod download
ARG GIT_COMMIT=unknown
RUN CGO_ENABLED=0 go build -ldflags "-X main.gitCommit=${GIT_COMMIT}" -o /orders-api .

# ---- final stage ----
FROM gcr.io/distroless/static-debian12:nonroot AS final
ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=$GIT_COMMIT
COPY --from=build /orders-api /orders-api
USER nonroot:nonroot
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD ["/orders-api", "-healthcheck"]
ENTRYPOINT ["/orders-api"]
