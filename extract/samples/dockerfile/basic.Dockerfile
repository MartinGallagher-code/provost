FROM node:18-alpine AS builder
WORKDIR /app
ARG NODE_ENV=production
ENV PORT=3000
ENV APP_NAME=myservice
COPY package*.json ./
RUN npm ci --only=production
EXPOSE 3000
LABEL maintainer="team@example.com"
LABEL version="1.2.0"

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app .
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "server.js"]
HEALTHCHECK --interval=30s CMD curl -f http://localhost:3000/health || exit 1
