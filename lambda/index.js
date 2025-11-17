const TurndownService = require('turndown');
const { JSDOM } = require('jsdom');

const DEFAULT_ATTACHMENT_TEMPLATE = '/img/{filename}';

function s(v) { return (v || '').toString().trim(); }

function buildAttachmentUrl({ filename, baseUrl, pageId, tpl, absolute }) {
  const encodedFilename = encodeURIComponent(s(filename));
  const rel = (tpl || DEFAULT_ATTACHMENT_TEMPLATE)
    .replace('{page_id}', s(pageId))
    .replace('{filename}', encodedFilename);
  return absolute && baseUrl ? `${baseUrl.replace(/\/$/, '')}${rel}` : rel;
}




function normalizeConfluenceXhtmlToHtml(xhtml, opts = {}) {
  const { base_url, page_id, attachment_url_template, prefer_absolute_urls } = opts;
  const dom = new JSDOM(`<root>${xhtml}</root>`);
  const doc = dom.window.document;

  function nodeToHtml(node) {
    if (!node) return '';
    const type = node.nodeType;
    if (type === 3 || type === 4) return node.nodeValue || '';
    if (type === 1) {
      const name = (node.nodeName || '').toLowerCase();

      if (name === 'ac:image') {
        let alt = s(node.getAttribute('ac:alt')) || s(node.getAttribute('alt'));
        let src = null;

        for (const c of node.children) {
          if (c.nodeName.toLowerCase() === 'ri:attachment') {
            const fn = s(c.getAttribute('ri:filename'));
            if (fn) {
              src = buildAttachmentUrl({ filename: fn, baseUrl: base_url, pageId: page_id, tpl: attachment_url_template, absolute: !!prefer_absolute_urls });
              if (!alt) alt = fn;
              break;
            }
          }
        }

        if (!src) {
          for (const c of node.children) {
            if (c.nodeName.toLowerCase() === 'ri:url') {
              const val = s(c.getAttribute('ri:value'));
              if (val) { src = val; break; }
            }
          }
        }

        if (src) {
          const altEsc = (alt || '').replace(/"/g, '&quot;');
          const srcEsc = src.replace(/"/g, '&quot;');
          return `<img src="${srcEsc}" alt="${altEsc}" />`;
        }
        return alt || '';
      }

      if (name.includes(':') && !name.startsWith('xml')) {
        let inner = '';
        for (const c of node.childNodes) inner += nodeToHtml(c);
        return inner;
      }

      const allowed = new Set(['p','br','strong','b','em','i','code','pre','a','ul','ol','li','h1','h2','h3','h4','h5','h6','img','table','tr','th','td']);
      if (allowed.has(name)) {
        let attrs = '';
        if (name === 'a') {
          const href = s(node.getAttribute('href'));
          if (href) attrs += ` href="${href.replace(/"/g,'&quot;')}"`;
        }
        if (name === 'img') {
          const src = s(node.getAttribute('src'));
          const alt = s(node.getAttribute('alt'));
          if (src) attrs += ` src="${src.replace(/"/g,'&quot;')}"`;
          if (alt) attrs += ` alt="${alt.replace(/"/g,'&quot;')}"`;
        }
        let inner = '';
        for (const c of node.childNodes) inner += nodeToHtml(c);
        if (name === 'br' || name === 'img') return `<${name}${attrs} />`;
        return `<${name}${attrs}>${inner}</${name}>`;
      }

      let inner = '';
      for (const c of node.childNodes) inner += nodeToHtml(c);
      return inner;
    }
    return '';
  }

  let html = '';
  for (const child of doc.documentElement.childNodes) {
    html += nodeToHtml(child);
  }
  return html;
}

function xhtmlToMarkdown(xhtml, opts = {}) {
  const normalized = normalizeConfluenceXhtmlToHtml(xhtml, opts);
  const turndown = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced' });

  // Taulukkotuki
  turndown.addRule('table', {
    filter: function (node) {
      return node.nodeName === 'TABLE';
    },
    replacement: function (content, node) {
      const rows = Array.from(node.querySelectorAll('tr')).map(tr => {
        const cells = Array.from(tr.children).map(td => {
          return (td.textContent || '').trim().replace(/\|/g, '\\|');
        });
        return cells;
      });

      if (!rows.length) return '';
      const header = rows[0];
      const aligns = header.map(() => '---');
      const body = rows.slice(1);

      const tableMarkdown = [
        `| ${header.join(' | ')} |`,
        `| ${aligns.join(' | ')} |`,
        ...body.map(r => `| ${r.join(' | ')} |`)
      ].join('\n');

      return `\n${tableMarkdown}\n\n`;
    }
  });

  // Rivinvaihdot <br>
  turndown.addRule('lineBreak', { filter: ['br'], replacement: () => '  \n' });

  return turndown.turndown(normalized).replace(/\n{3,}/g, '\n\n').trim() + '\n';
}

exports.handler = async (event) => {
  try {
    let bodyRaw = (event && event.body) || '';
    if (event && event.isBase64Encoded && bodyRaw) {
      bodyRaw = Buffer.from(bodyRaw, 'base64').toString('utf8');
    }
    let payload = {};
    if (typeof bodyRaw === 'string' && bodyRaw.trim()) {
      try { payload = JSON.parse(bodyRaw); } catch { payload = { xhtml: bodyRaw }; }
    }
    if (event && typeof event === 'object') {
      for (const k of ['xhtml','base_url','page_id','attachment_url_template','prefer_absolute_urls']) {
        if (event[k] !== undefined && payload[k] === undefined) payload[k] = event[k];
      }
    }
    const xhtml = payload.xhtml;
    if (!xhtml) {
      return { statusCode: 400, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ error: "Missing 'xhtml' in request body" }) };
    }
    const md = xhtmlToMarkdown(xhtml, { base_url: payload.base_url, page_id: String(payload.page_id || ''), attachment_url_template: payload.attachment_url_template, prefer_absolute_urls: !!payload.prefer_absolute_urls });
    return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ markdown: md }) };
  } catch (e) {
    return { statusCode: 500, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ error: String(e) }) };
  }
};