// NKTouch paid-service entitlements. No local GPL Lua functions are gated here.
// SPDX-License-Identifier: GPL-3.0-or-later
import { createHash, createPrivateKey, createPublicKey, randomUUID, sign, timingSafeEqual, verify } from 'node:crypto';

const MAX_TTL = 7 * 24 * 3600;
const MAX_TOKEN_LENGTH = 8192;
const HEADER_TYPE = 'NKTOUCH-SERVICE-LEASE';
const ID_PATTERN = /^[a-zA-Z0-9._:-]{1,100}$/;

export class LeaseError extends Error {
  constructor(code) { super(code); this.name = 'LeaseError'; this.code = code; }
}
const fail = code => { throw new LeaseError(code); };
const encode = value => Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');
const decode = value => {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) fail('MALFORMED_TOKEN');
  const bytes = Buffer.from(value, 'base64url');
  if (bytes.toString('base64url') !== value) fail('MALFORMED_TOKEN');
  try { return JSON.parse(bytes.toString('utf8')); } catch { return fail('MALFORMED_TOKEN'); }
};
const requireId = x => typeof x === 'string' && ID_PATTERN.test(x);
const requireSeconds = x => Number.isSafeInteger(x) && x >= 0;
const requireScopes = x => Array.isArray(x) && x.length > 0 && x.length <= 24 && x.every(requireId) && new Set(x).size === x.length;

export function deviceFingerprint(devicePublicKeyPem) {
  let key;
  try { key = createPublicKey(devicePublicKeyPem); } catch { return fail('INVALID_DEVICE_KEY'); }
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') fail('INVALID_DEVICE_KEY');
  const der = key.export({ type: 'spki', format: 'der' });
  return createHash('sha256').update(der).digest('hex');
}

// Server only. Never ship privateKeyPem or Supabase credentials with the iOS tweak.
export function issueLease({ licenseId, devicePublicKeyPem, scopes, nowSeconds, ttlSeconds = 86400, kid = 'v1' }, privateKeyPem) {
  if (!requireId(licenseId) || !requireId(kid) || !requireScopes(scopes)) fail('INVALID_CLAIMS');
  if (!requireSeconds(nowSeconds) || !Number.isSafeInteger(ttlSeconds) || ttlSeconds < 60 || ttlSeconds > MAX_TTL) fail('INVALID_TTL');
  let key;
  try { key = createPrivateKey(privateKeyPem); } catch { return fail('INVALID_SIGNING_KEY'); }
  if (key.asymmetricKeyType !== 'ed25519') fail('INVALID_SIGNING_KEY');
  const header = { typ: HEADER_TYPE, v: 1, kid };
  const payload = {
    iss: 'nktouch-service', aud: 'nktouch-paid-api', sub: licenseId,
    device: deviceFingerprint(devicePublicKeyPem), scopes,
    iat: nowSeconds, nbf: nowSeconds, exp: nowSeconds + ttlSeconds, jti: randomUUID(),
  };
  const body = `${encode(header)}.${encode(payload)}`;
  return `${body}.${sign(null, Buffer.from(body, 'ascii'), key).toString('base64url')}`;
}

// Validates a signed lease for access to optional server-hosted services.
export function verifyLease(token, { publicKeys, devicePublicKeyPem, nowSeconds, expectedScope = undefined, skewSeconds = 60 }) {
  if (typeof token !== 'string' || token.length > MAX_TOKEN_LENGTH) fail('MALFORMED_TOKEN');
  const parts = token.split('.');
  if (parts.length !== 3) fail('MALFORMED_TOKEN');
  const [h, p, s] = parts;
  const header = decode(h), payload = decode(p);
  if (header === null || typeof header !== 'object' || Array.isArray(header) ||
      header.typ !== HEADER_TYPE || header.v !== 1 || !requireId(header.kid)) fail('INVALID_HEADER');
  if (!publicKeys || !Object.hasOwn(publicKeys, header.kid)) fail('UNKNOWN_KEY');
  let key;
  try { key = createPublicKey(publicKeys[header.kid]); } catch { return fail('UNKNOWN_KEY'); }
  if (key.asymmetricKeyType !== 'ed25519') fail('UNKNOWN_KEY');
  if (!/^[A-Za-z0-9_-]+$/.test(s) || Buffer.from(s, 'base64url').toString('base64url') !== s) fail('MALFORMED_TOKEN');
  if (!verify(null, Buffer.from(`${h}.${p}`, 'ascii'), key, Buffer.from(s, 'base64url'))) fail('BAD_SIGNATURE');
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload) ||
      payload.iss !== 'nktouch-service' || payload.aud !== 'nktouch-paid-api' ||
      !requireId(payload.sub) || !requireScopes(payload.scopes) || !requireId(payload.jti) ||
      !requireSeconds(payload.iat) || !requireSeconds(payload.nbf) || !requireSeconds(payload.exp) ||
      payload.exp <= payload.iat || payload.exp - payload.iat > MAX_TTL || payload.nbf < payload.iat ||
      !/^[a-f0-9]{64}$/.test(payload.device)) fail('INVALID_CLAIMS');
  if (!requireSeconds(nowSeconds) || !Number.isSafeInteger(skewSeconds) || skewSeconds < 0 || skewSeconds > 300) fail('INVALID_CLOCK');
  if (payload.iat > nowSeconds + skewSeconds || payload.nbf > nowSeconds + skewSeconds) fail('NOT_YET_VALID');
  if (payload.exp <= nowSeconds - skewSeconds) fail('EXPIRED');
  if (typeof expectedScope !== 'undefined' && (!requireId(expectedScope) || !payload.scopes.includes(expectedScope))) fail('SCOPE_DENIED');
  const actual = Buffer.from(deviceFingerprint(devicePublicKeyPem), 'hex');
  const claimed = Buffer.from(payload.device, 'hex');
  if (!timingSafeEqual(actual, claimed)) fail('WRONG_DEVICE');
  return Object.freeze({ ...payload, scopes: Object.freeze([...payload.scopes]) });
}
