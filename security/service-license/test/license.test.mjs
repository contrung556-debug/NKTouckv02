// SPDX-License-Identifier: GPL-3.0-or-later
import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { issueLease, verifyLease, LeaseError, deviceFingerprint } from '../lease.mjs';
import { createChallenge, signProof, verifyProof } from '../proof.mjs';

const ed = generateKeyPairSync('ed25519');
const device = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const other = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const pub = key => key.export({ type:'spki', format:'pem' });
const priv = key => key.export({ type:'pkcs8', format:'pem' });
const nowSeconds = 1900000000;
const args = { licenseId:'lic-test-001', devicePublicKeyPem:pub(device.publicKey), scopes:['cloud-sync','priority-support'], nowSeconds, ttlSeconds:3600, kid:'key-1' };
const keys = { 'key-1':pub(ed.publicKey) };
const options = { publicKeys:keys, devicePublicKeyPem:args.devicePublicKeyPem, nowSeconds, expectedScope:'cloud-sync' };
const issue = (overrides = {}) => issueLease({ ...args, ...overrides }, priv(ed.privateKey));
const expected = code => e => e instanceof LeaseError && e.code === code;

test('signed lease verifies, and fingerprints use public key DER', () => {
  const claims = verifyLease(issue(), options);
  assert.equal(claims.sub, args.licenseId);
  assert.equal(claims.device, deviceFingerprint(args.devicePublicKeyPem));
  assert.ok(Object.isFrozen(claims));
});
test('modified data fails signature verification', () => {
  const [h,p,s] = issue().split('.');
  const payload = JSON.parse(Buffer.from(p,'base64url').toString());
  payload.scopes.push('everything');
  const modified = Buffer.from(JSON.stringify(payload)).toString('base64url');
  assert.throws(() => verifyLease([h, modified, s].join('.'), options), expected('BAD_SIGNATURE'));
});
test('mismatched device denied', () => {
  assert.throws(() => verifyLease(issue(), {...options,devicePublicKeyPem:pub(other.publicKey)}), expected('WRONG_DEVICE'));
});
test('expired and future leases denied', () => {
  assert.throws(() => verifyLease(issue(), {...options,nowSeconds:nowSeconds+4000}), expected('EXPIRED'));
  assert.throws(() => verifyLease(issue({nowSeconds:nowSeconds+1000}),options), expected('NOT_YET_VALID'));
});
test('scope, signing key and lifetime constrained', () => {
  assert.throws(() => verifyLease(issue(), {...options,expectedScope:'admin'}), expected('SCOPE_DENIED'));
  assert.throws(() => verifyLease(issue(), {...options,publicKeys:{}}), expected('UNKNOWN_KEY'));
  assert.throws(() => issue({ttlSeconds:8*86400}), expected('INVALID_TTL'));
  assert.throws(() => issue({scopes:['cloud-sync','cloud-sync']}),expected('INVALID_CLAIMS'));
});
test('malformed, oversized and non-canonical tokens denied', () => {
  assert.throws(() => verifyLease('x', options), expected('MALFORMED_TOKEN'));
  assert.throws(() => verifyLease('a'.repeat(8193), options), expected('MALFORMED_TOKEN'));
  const t = issue();
  assert.throws(() => verifyLease(t+'=', options), expected('MALFORMED_TOKEN'));
});
test('P-256 challenge binds action, license and public key', () => {
  const claims={ challenge:createChallenge(), action:'renew', licenseId:args.licenseId, devicePublicKeyPem:args.devicePublicKeyPem };
  const proof=signProof(claims,priv(device.privateKey));
  assert.equal(verifyProof(claims,proof),true);
  assert.equal(verifyProof({...claims,action:'activate'},proof),false);
  assert.equal(verifyProof({...claims,licenseId:'different'},proof),false);
  assert.equal(verifyProof({...claims,devicePublicKeyPem:pub(other.publicKey)},proof),false);
  assert.equal(verifyProof({...claims,challenge:createChallenge()},proof),false);
});
test('challenge single-use enforcement belongs to server', () => {
  const used=new Set();
  const claims={ challenge:createChallenge(), action:'renew', licenseId:args.licenseId, devicePublicKeyPem:args.devicePublicKeyPem };
  const proof=signProof(claims,priv(device.privateKey));
  const consume=() => !used.has(claims.challenge) && verifyProof(claims,proof) && (used.add(claims.challenge),true);
  assert.equal(consume(),true);
  assert.equal(consume(),false);
});
