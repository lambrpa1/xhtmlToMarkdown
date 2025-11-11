const express = require('express');
const bodyParser = require('body-parser');
const { handler } = require('../lambda/index');

const app = express();
app.use(bodyParser.text({ type: '*/*' })); // sallitaan myös raw XHTML

app.post('/convert', async (req, res) => {
  const event = {
    isBase64Encoded: false,
    body: req.get('content-type')?.includes('application/json')
      ? req.body
      : JSON.stringify({ xhtml: req.body })
  };
  const out = await handler(event);
  res.status(out.statusCode).set(out.headers || {}).send(out.body);
});

app.listen(3000, () => console.log('Dev server http://localhost:3000/convert'));