#!/usr/bin/env node
/**
 * PortHub — backend opcional (Node.js 18+, sem dependências).
 *
 * 1. Proxy de cache da GitHub API:   GET /gh/<caminho da API>
 *    Ex.: /gh/repos/diasurgical/devilutionX/releases?per_page=10
 *    - Usa GITHUB_TOKEN (se definido) para 5000 req/h compartilhadas entre
 *      todos os clientes da rede.
 *    - Cache em memória + disco (data/gh-cache.json) com ETag e TTL.
 *
 * 2. PortHub Compatibility Database (relatos da comunidade, estilo ProtonDB):
 *    GET  /api/reports?game=<id>      → { reports: [...] }
 *    POST /api/reports                → grava um relato (JSON)
 *    GET  /api/summary?game=<id>      → agregado (classificação, FPS médio…)
 *    GET  /api/health
 *
 * Uso:  GITHUB_TOKEN=ghp_xxx PORT=8787 node server.js
 */
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const PORT = Number(process.env.PORT || 8787);
const TOKEN = process.env.GITHUB_TOKEN || '';
const TTL_MS = Number(process.env.CACHE_TTL_SECONDS || 600) * 1000;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const REPORTS_FILE = path.join(DATA_DIR, 'reports.json');
const CACHE_FILE = path.join(DATA_DIR, 'gh-cache.json');
const MAX_BODY = 32 * 1024;
const RATINGS = ['platinum', 'gold', 'silver', 'bronze', 'borked'];

fs.mkdirSync(DATA_DIR, { recursive: true });

// ----------------------------------------------------------------- armazenamento
function loadJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

/** Escrita atômica (arquivo temporário + rename). */
function saveJson(file, data) {
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, file);
}

const reports = loadJson(REPORTS_FILE, []);
const ghCache = new Map(Object.entries(loadJson(CACHE_FILE, {})));
let cacheDirty = false;
setInterval(() => {
  if (!cacheDirty) return;
  cacheDirty = false;
  // Mantém no máximo 5000 entradas (as mais recentes).
  const entries = [...ghCache.entries()].sort((a, b) => b[1].fetchedAt - a[1].fetchedAt).slice(0, 5000);
  saveJson(CACHE_FILE, Object.fromEntries(entries));
}, 15000).unref();

// ------------------------------------------------------------------- utilidades
function send(res, status, body, headers = {}) {
  const data = typeof body === 'string' ? body : JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, If-None-Match',
    ...headers,
  });
  res.end(data);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new Error('payload muito grande'));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

const str = (v, max = 200) => (typeof v === 'string' ? v.slice(0, max).trim() : undefined);
const num = (v, min, max) => (typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max ? v : undefined);

// Limite simples de envio de relatos por IP (10 por hora).
const postLog = new Map();
function allowPost(ip) {
  const now = Date.now();
  const list = (postLog.get(ip) || []).filter((t) => now - t < 3600_000);
  if (list.length >= 10) return false;
  list.push(now);
  postLog.set(ip, list);
  return true;
}

// ------------------------------------------------------------- proxy do GitHub
async function proxyGitHub(req, res, apiPath) {
  if (!/^\/[A-Za-z0-9._~\-/%?=&,:+]*$/.test(apiPath)) return send(res, 400, { message: 'caminho inválido' });
  const url = `https://api.github.com${apiPath}`;
  const cached = ghCache.get(url);
  const fresh = cached && Date.now() - cached.fetchedAt < TTL_MS;

  const reply = (entry, hit) => {
    if (entry.status === 200 && req.headers['if-none-match'] === entry.etag) {
      return send(res, 304, '', { ETag: entry.etag, 'X-PortHub-Cache': hit });
    }
    send(res, entry.status, entry.body, { ETag: entry.etag || '', 'X-PortHub-Cache': hit });
  };

  if (fresh) return reply(cached, 'HIT');

  const headers = {
    Accept: req.headers.accept || 'application/vnd.github+json',
    'User-Agent': 'PortHub-Backend',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  if (TOKEN) headers.Authorization = `Bearer ${TOKEN}`;
  if (cached?.upstreamEtag) headers['If-None-Match'] = cached.upstreamEtag;

  try {
    const r = await fetch(url, { headers, signal: AbortSignal.timeout(20000) });
    if (r.status === 304 && cached) {
      cached.fetchedAt = Date.now();
      cacheDirty = true;
      return reply(cached, 'REVALIDATED');
    }
    const body = await r.text();
    if (r.status === 200 || r.status === 404) {
      const entry = {
        status: r.status,
        body,
        upstreamEtag: r.headers.get('etag'),
        etag: `"${crypto.createHash('sha1').update(body).digest('hex')}"`,
        fetchedAt: Date.now(),
      };
      ghCache.set(url, entry);
      cacheDirty = true;
      return reply(entry, 'MISS');
    }
    if (cached) return reply(cached, 'STALE');
    send(res, r.status, body);
  } catch (e) {
    if (cached) return reply(cached, 'STALE');
    send(res, 502, { message: `GitHub indisponível: ${e.message}` });
  }
}

// ------------------------------------------------------------ relatos/compat DB
function validateReport(j) {
  const rating = RATINGS.includes(j.rating) ? j.rating : null;
  const gameId = str(j.game_id, 200);
  const platform = ['android', 'linux', 'windows'].includes(j.platform) ? j.platform : null;
  if (!rating || !gameId || !platform) return null;
  return {
    id: crypto.randomUUID(),
    game_id: gameId,
    platform,
    device_model: str(j.device_model, 120) || 'Desconhecido',
    soc: str(j.soc, 120),
    gpu: str(j.gpu, 120),
    ram_mb: num(j.ram_mb, 128, 1 << 20),
    os_version: str(j.os_version, 80),
    rating,
    fps: num(j.fps, 1, 1000),
    issues: Array.isArray(j.issues) ? j.issues.slice(0, 10).map((i) => str(i, 80)).filter(Boolean) : [],
    notes: str(j.notes, 1000) || '',
    game_version: str(j.game_version, 60),
    created_at: new Date().toISOString(),
  };
}

function summary(gameId) {
  const list = reports.filter((r) => r.game_id === gameId);
  const counts = Object.fromEntries(RATINGS.map((r) => [r, 0]));
  for (const r of list) counts[r.rating]++;
  const fps = list.map((r) => r.fps).filter((f) => typeof f === 'number');
  const top = RATINGS.reduce((a, b) => (counts[b] > counts[a] ? b : a), RATINGS[0]);
  return {
    game_id: gameId,
    total: list.length,
    rating: list.length ? top : null,
    counts,
    average_fps: fps.length ? fps.reduce((a, b) => a + b, 0) / fps.length : null,
  };
}

// ---------------------------------------------------------------------- rotas
const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://localhost');
  try {
    if (req.method === 'OPTIONS') return send(res, 204, '');

    if (u.pathname.startsWith('/gh/') && req.method === 'GET') {
      return proxyGitHub(req, res, u.pathname.slice(3) + u.search);
    }
    if (u.pathname === '/api/health') {
      return send(res, 200, { ok: true, reports: reports.length, cache: ghCache.size, token: Boolean(TOKEN) });
    }
    if (u.pathname === '/api/reports' && req.method === 'GET') {
      const game = u.searchParams.get('game');
      if (!game) return send(res, 400, { message: 'parâmetro game obrigatório' });
      const list = reports.filter((r) => r.game_id === game).slice(-500).reverse();
      return send(res, 200, { reports: list });
    }
    if (u.pathname === '/api/reports' && req.method === 'POST') {
      const ip = req.socket.remoteAddress || '?';
      if (!allowPost(ip)) return send(res, 429, { message: 'muitos relatos; tente mais tarde' });
      const report = validateReport(JSON.parse(await readBody(req)));
      if (!report) return send(res, 400, { message: 'relato inválido' });
      reports.push(report);
      saveJson(REPORTS_FILE, reports);
      return send(res, 201, report);
    }
    if (u.pathname === '/api/summary' && req.method === 'GET') {
      const game = u.searchParams.get('game');
      if (!game) return send(res, 400, { message: 'parâmetro game obrigatório' });
      return send(res, 200, summary(game));
    }
    send(res, 404, { message: 'não encontrado' });
  } catch (e) {
    send(res, 500, { message: e.message });
  }
});

server.listen(PORT, () => {
  console.log(`PortHub backend em http://0.0.0.0:${PORT}  (token GitHub: ${TOKEN ? 'sim' : 'não'})`);
});
