FROM alpine:3.20

LABEL org.opencontainers.image.source="https://github.com/rolfwalker71-commits/autototp"
LABEL org.opencontainers.image.description="Autototp Windows single-file builds (WPF) for win-x86 and win-arm64."
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app
COPY publish/ /app/

CMD ["sh", "-c", "echo 'Autototp Windows builds: win-x86 and win-arm64. Copy the matching exe to a Windows PC.' && ls -la /app"]
