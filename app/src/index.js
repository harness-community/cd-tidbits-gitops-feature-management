const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'unknown';
const APP_VERSION = process.env.APP_VERSION || 'dev';

app.get('/', (req, res) => {
  res.json({
    app: 'gitops-demo',
    version: APP_VERSION,
    environment: ENVIRONMENT,
    message: `Hello from Harness GitOps! Running in ${ENVIRONMENT}.`,
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.listen(PORT, () => {
  console.log(`gitops-demo v${APP_VERSION} (${ENVIRONMENT}) listening on port ${PORT}`);
});
