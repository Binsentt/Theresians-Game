FROM node:22-alpine
ENV NODE_ENV=production PORT=3000 OTA_STORAGE_DIR=/data
WORKDIR /app
COPY --chown=node:node server.mjs ./server.mjs
COPY --chown=node:node public ./public
RUN mkdir -p /data && chown node:node /data
USER node
EXPOSE 3000
CMD ["node", "server.mjs"]
