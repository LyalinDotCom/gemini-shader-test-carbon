import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, 'public');
const RAW_CLIPS_DIR = path.join(__dirname, 'raw_clips');
const PORT = Number(process.env.PORT) || 3000;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.glsl': 'text/plain; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.mp4': 'video/mp4',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

function resolveSafePath(urlPathname) {
  let decoded;
  try {
    decoded = decodeURIComponent(urlPathname);
  } catch {
    return null;
  }

  if (decoded === '/' || decoded === '') {
    return path.join(PUBLIC_DIR, 'index.html');
  }

  if (decoded.startsWith('/raw_clips/')) {
    const rel = decoded.slice('/raw_clips/'.length);
    const full = path.resolve(RAW_CLIPS_DIR, rel);
    if (!full.startsWith(RAW_CLIPS_DIR + path.sep)) return null;
    return full;
  }

  const rel = decoded.replace(/^\/+/, '');
  const full = path.resolve(PUBLIC_DIR, rel);
  if (!full.startsWith(PUBLIC_DIR + path.sep)) return null;
  return full;
}

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Method Not Allowed');
    return;
  }

  const reqUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const filePath = resolveSafePath(reqUrl.pathname);

  if (!filePath) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Forbidden');
    return;
  }

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not Found');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    const total = stat.size;
    const rangeHeader = req.headers.range;

    if (rangeHeader) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
      if (!match) {
        res.writeHead(416, { 'Content-Range': `bytes */${total}` });
        res.end();
        return;
      }

      let start;
      let end;
      if (match[1] === '' && match[2] !== '') {
        const suffixLen = Number(match[2]);
        start = Math.max(total - suffixLen, 0);
        end = total - 1;
      } else {
        start = Number(match[1]);
        end = match[2] !== '' ? Math.min(Number(match[2]), total - 1) : total - 1;
      }

      if (Number.isNaN(start) || Number.isNaN(end) || start >= total || start > end || start < 0) {
        res.writeHead(416, { 'Content-Range': `bytes */${total}` });
        res.end();
        return;
      }

      const chunkSize = end - start + 1;
      res.writeHead(206, {
        'Content-Range': `bytes ${start}-${end}/${total}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': chunkSize,
        'Content-Type': contentType,
        'Cache-Control': 'no-cache',
      });

      if (req.method === 'HEAD') {
        res.end();
        return;
      }

      const stream = fs.createReadStream(filePath, { start, end });
      stream.on('error', () => {
        if (!res.headersSent) res.writeHead(500);
        res.destroy();
      });
      req.on('close', () => stream.destroy());
      stream.pipe(res);
      return;
    }

    res.writeHead(200, {
      'Accept-Ranges': 'bytes',
      'Content-Length': total,
      'Content-Type': contentType,
      'Cache-Control': 'no-cache',
    });

    if (req.method === 'HEAD') {
      res.end();
      return;
    }

    const stream = fs.createReadStream(filePath);
    stream.on('error', () => {
      if (!res.headersSent) res.writeHead(500);
      res.destroy();
    });
    req.on('close', () => stream.destroy());
    stream.pipe(res);
  });
});

server.listen(PORT, () => {
  console.log(`Gemini Video 2 GLSL server running at http://localhost:${PORT}`);
});
