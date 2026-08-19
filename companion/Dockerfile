FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /aw-companion .

FROM scratch
COPY --from=build /aw-companion /aw-companion
EXPOSE 8089
ENTRYPOINT ["/aw-companion"]
