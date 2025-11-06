const { handler } = require('./index'); // tai polku canvasin tiedostoon
const fs = require('fs');

(async () => {
  const xhtml = fs.readFileSync('./testdata/sample.xhtml', 'utf8');

  // API Gateway -proxy -event (suositeltu)
  const event = {
    isBase64Encoded: false,
    body: JSON.stringify({
      xhtml,
      base_url: 'https://confluence.example.com',
      page_id: '123456',
      prefer_absolute_urls: true
    })
  };

  // Voi kokeilla myös non-proxy -muotoa:
  // const event = { xhtml, base_url: 'https://confluence.example.com', page_id: '123456', prefer_absolute_urls: true };

  try {
    const res = await handler(event);
    console.log('Status:', res.statusCode);
    const body = JSON.parse(res.body);
    console.log('\n--- MARKDOWN ---\n');
    console.log(body.markdown);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
})();