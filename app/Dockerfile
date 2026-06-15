FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine
WORKDIR /app
COPY --from=base /app/node_modules ./node_modules
COPY src/ ./src/
COPY package.json ./

EXPOSE 3000
USER node

CMD ["node", "src/index.js"]
