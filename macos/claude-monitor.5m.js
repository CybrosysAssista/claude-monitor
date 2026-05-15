#!/usr/bin/env node

// <xbar.title>Claude Monitor</xbar.title>
// <xbar.version>v1.0.0</xbar.version>
// <xbar.author>Cybrosys Assista</xbar.author>
// <xbar.author.github>CybrosysAssista</xbar.author.github>
// <xbar.desc>Track Claude and Codex AI usage limits in the macOS menu bar</xbar.desc>
// <xbar.dependencies>node</xbar.dependencies>
// <xbar.abouturl>https://github.com/CybrosysAssista/claude-monitor</xbar.abouturl>

'use strict';

const fs   = require('fs');
const os   = require('os');
const path = require('path');

// ── Constants ─────────────────────────────────────────────────────────────────

const SCRIPT_DIR     = path.dirname(process.argv[1]);
const CLAUDE_CREDS   = path.join(os.homedir(), '.claude', '.credentials.json');
const CODEX_CREDS    = path.join(os.homedir(), '.codex', 'auth.json');

const CLAUDE_REFRESH = 'https://platform.claude.com/v1/oauth/token';
const CLAUDE_USAGE   = 'https://api.anthropic.com/api/oauth/usage';
const CLAUDE_ID      = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
const CLAUDE_BETA    = 'oauth-2025-04-20';

const CODEX_REFRESH  = 'https://auth.openai.com/oauth/token';
const CODEX_USAGE    = 'https://chatgpt.com/backend-api/wham/usage';
const CODEX_ID       = 'app_EMoamEEZ73f0CkXaXp7hrann';

// ── Icons ─────────────────────────────────────────────────────────────────────

function loadIcon(name) {
    try {
        return fs.readFileSync(path.join(SCRIPT_DIR, `${name}.svg`)).toString('base64');
    } catch {
        return null;
    }
}

function iconParam(base64) {
    return base64 ? ` | image=${base64} imageWidth=16 imageHeight=16` : '';
}

// ── HTTP ──────────────────────────────────────────────────────────────────────

function nodeFetch(url, options = {}) {
    return new Promise((resolve, reject) => {
        const lib    = url.startsWith('https') ? require('https') : require('http');
        const parsed = new URL(url);
        const body   = options.body ? options.body.toString() : null;

        const req = lib.request(
            {
                hostname: parsed.hostname,
                path:     parsed.pathname + parsed.search,
                method:   options.method ?? 'GET',
                headers:  options.headers ?? {},
            },
            (res) => {
                const chunks = [];
                res.on('data', c => chunks.push(c));
                res.on('end', () => {
                    const text = Buffer.concat(chunks).toString('utf8');
                    resolve({
                        ok:     res.statusCode >= 200 && res.statusCode < 300,
                        status: res.statusCode,
                        json:   () => Promise.resolve(JSON.parse(text)),
                        text:   () => Promise.resolve(text),
                    });
                });
            },
        );

        req.on('error', reject);
        if (body) req.write(body);
        req.end();
    });
}

const apiFetch = typeof globalThis.fetch === 'function'
    ? (url, opts) => globalThis.fetch(url, opts)
    : nodeFetch;

// ── Normalize ─────────────────────────────────────────────────────────────────

function clamp(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return null;
    return Math.max(0, Math.min(100, n));
}

function unixToIso(v) {
    const s = Number(v);
    return Number.isFinite(s) ? new Date(s * 1000).toISOString() : null;
}

function normalizeClaudeUsage(payload) {
    return {
        sessionRemainingPct: clamp(100 - Number(payload?.five_hour?.utilization)),
        weeklyRemainingPct:  clamp(100 - Number(payload?.seven_day?.utilization)),
        sessionResetsAtIso:  payload?.five_hour?.resets_at ?? null,
        weeklyResetsAtIso:   payload?.seven_day?.resets_at ?? null,
    };
}

function normalizeCodexUsage(payload) {
    const p = payload?.rate_limit?.primary_window;
    const s = payload?.rate_limit?.secondary_window;
    return {
        sessionRemainingPct: clamp(100 - Number(p?.used_percent)),
        weeklyRemainingPct:  clamp(100 - Number(s?.used_percent)),
        sessionResetsAtIso:  unixToIso(p?.reset_at),
        weeklyResetsAtIso:   unixToIso(s?.reset_at),
    };
}

// ── Auth helpers ──────────────────────────────────────────────────────────────

function isExpired(expiry) {
    if (!expiry) return false;
    const ms = typeof expiry === 'number'
        ? (expiry > 1e12 ? expiry : expiry * 1000)
        : Date.parse(expiry);
    return Number.isFinite(ms) && Date.now() >= ms;
}

async function postForm(url, params) {
    const res = await apiFetch(url, {
        method:  'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body:    new URLSearchParams(params),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
}

// ── Claude provider ───────────────────────────────────────────────────────────

async function refreshClaude(refreshToken) {
    const data = await postForm(CLAUDE_REFRESH, {
        grant_type:    'refresh_token',
        refresh_token: refreshToken,
        client_id:     CLAUDE_ID,
    });
    const token = data.access_token ?? data.accessToken;
    if (!token) throw new Error('No access token in Claude refresh response');
    return token;
}

async function fetchClaudeUsage(token) {
    return apiFetch(CLAUDE_USAGE, {
        headers: { authorization: `Bearer ${token}`, 'anthropic-beta': CLAUDE_BETA },
    });
}

async function getClaudeData() {
    let creds;
    try { creds = JSON.parse(fs.readFileSync(CLAUDE_CREDS, 'utf8')); }
    catch { return { error: 'credentials not found (~/.claude/.credentials.json)' }; }

    const oauth   = creds?.claudeAiOauth;
    if (!oauth)   return { error: 'missing claudeAiOauth in credentials' };

    const refresh = oauth.refreshToken ?? oauth.refresh_token;
    const expiry  = oauth.expiresAt ?? oauth.expires_at;
    let   token   = oauth.accessToken ?? oauth.access_token;

    try {
        if (!token || isExpired(expiry)) token = await refreshClaude(refresh);

        let res = await fetchClaudeUsage(token);
        if (res.status === 401) {
            token = await refreshClaude(refresh);
            res   = await fetchClaudeUsage(token);
        }

        if (!res.ok) return { error: `Claude API ${res.status}` };
        return normalizeClaudeUsage(await res.json());
    } catch (e) {
        return { error: e.message };
    }
}

// ── Codex provider ────────────────────────────────────────────────────────────

async function refreshCodex(refreshToken) {
    const data = await postForm(CODEX_REFRESH, {
        grant_type:    'refresh_token',
        client_id:     CODEX_ID,
        refresh_token: refreshToken,
    });
    if (!data.access_token) throw new Error('No access token in Codex refresh response');
    return data.access_token;
}

async function fetchCodexUsage(token, accountId) {
    const headers = { authorization: `Bearer ${token}` };
    if (accountId) headers['ChatGPT-Account-Id'] = accountId;
    return apiFetch(CODEX_USAGE, { headers });
}

async function getCodexData() {
    let creds;
    try { creds = JSON.parse(fs.readFileSync(CODEX_CREDS, 'utf8')); }
    catch { return { error: 'credentials not found (~/.codex/auth.json)' }; }

    const tokens    = creds?.tokens;
    const refresh   = tokens?.refresh_token;
    const accountId = tokens?.account_id;
    let   token     = tokens?.access_token;

    if (!token && !refresh) return { error: 'missing tokens in credentials' };

    try {
        if (!token) token = await refreshCodex(refresh);

        let res = await fetchCodexUsage(token, accountId);
        if (res.status === 401) {
            token = await refreshCodex(refresh);
            res   = await fetchCodexUsage(token, accountId);
        }

        if (!res.ok) return { error: `Codex API ${res.status}` };
        return normalizeCodexUsage(await res.json());
    } catch (e) {
        return { error: e.message };
    }
}

// ── Formatting ────────────────────────────────────────────────────────────────

function dotColor(pct) {
    if (pct === null) return '#64748b';
    if (pct >= 80)    return '#10b981';
    if (pct >= 50)    return '#34d399';
    if (pct >= 30)    return '#fbbf24';
    if (pct >= 15)    return '#f97316';
    return '#ef4444';
}

function fmtUsed(pct) {
    return pct === null ? '--' : `${Math.round(100 - pct)}% used`;
}

function fmtResets(iso) {
    if (!iso) return '--';
    const diff = new Date(iso).getTime() - Date.now();
    if (diff <= 0) return '--';
    const m   = Math.floor(diff / 60000);
    const d   = Math.floor(m / 1440);
    const h   = Math.floor((m % 1440) / 60);
    const min = m % 60;
    const parts = [];
    if (d)   parts.push(`${d}d`);
    if (h)   parts.push(`${h}h`);
    if (min || !parts.length) parts.push(`${min}m`);
    return `resets in ${parts.join(' ')}`;
}

function minPct(...vals) {
    const valid = vals.filter(v => v !== null);
    return valid.length ? Math.min(...valid) : null;
}

// ── Output ────────────────────────────────────────────────────────────────────

(async () => {
    const claudeIcon = loadIcon('claude');
    const codexIcon  = loadIcon('codex');

    const [clResult, coResult] = await Promise.allSettled([getClaudeData(), getCodexData()]);
    const cl = clResult.status === 'fulfilled' ? clResult.value : { error: clResult.reason?.message };
    const co = coResult.status === 'fulfilled' ? coResult.value : { error: coResult.reason?.message };

    const clMin = cl.error ? null : minPct(cl.sessionRemainingPct, cl.weeklyRemainingPct);
    const coMin = co.error ? null : minPct(co.sessionRemainingPct, co.weeklyRemainingPct);

    const clUsed = clMin === null ? '?' : `${Math.round(100 - clMin)}%`;
    const coUsed = coMin === null ? '?' : `${Math.round(100 - coMin)}%`;

    // ── Menu bar ──────────────────────────────────────────────────────────────
    console.log(`${clUsed}  ${coUsed}`);
    console.log('---');

    // ── Claude section ────────────────────────────────────────────────────────
    console.log(`Claude${iconParam(claudeIcon)}`);
    if (cl.error) {
        console.log(`-- ⚠ ${cl.error} | color=#64748b`);
    } else {
        const cs = cl.sessionRemainingPct;
        const cw = cl.weeklyRemainingPct;
        console.log(`-- Session   ${fmtUsed(cs).padEnd(12)} ${fmtResets(cl.sessionResetsAtIso)} | color=${dotColor(cs)}`);
        console.log(`-- Weekly    ${fmtUsed(cw).padEnd(12)} ${fmtResets(cl.weeklyResetsAtIso)} | color=${dotColor(cw)}`);
    }

    console.log('---');

    // ── Codex section ─────────────────────────────────────────────────────────
    console.log(`Codex${iconParam(codexIcon)}`);
    if (co.error) {
        console.log(`-- ⚠ ${co.error} | color=#64748b`);
    } else {
        const cs = co.sessionRemainingPct;
        const cw = co.weeklyRemainingPct;
        console.log(`-- Session   ${fmtUsed(cs).padEnd(12)} ${fmtResets(co.sessionResetsAtIso)} | color=${dotColor(cs)}`);
        console.log(`-- Weekly    ${fmtUsed(cw).padEnd(12)} ${fmtResets(co.weeklyResetsAtIso)} | color=${dotColor(cw)}`);
    }

    console.log('---');
    console.log('↺ Refresh | refresh=true');
    console.log('GitHub | href=https://github.com/CybrosysAssista/claude-monitor');
    console.log('Cybrosys Assista | href=https://assista.cybrosys.com');
})();
