// Challenge-response proof of possession, for activation and renewal.
// SPDX-License-Identifier: GPL-3.0-or-later
import { randomBytes, createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';
import { deviceFingerprint, LeaseError } from './lease.mjs';
const pattern = /^[A-Za-z0-9._:-]{1,100}$/;
const valid = x => typeof x === 'string' && pattern.test(x);

export function createChallenge() { return randomBytes(32).toString('base64url'); }

export function proofBytes({ challenge, action, licenseId, devicePublicKeyPem }) {
  if (typeof challenge !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(challenge) ||
      !['activate', 'renew'].includes(action) || !valid(licenseId)) throw new LeaseError('INVALID_PROOF_CLAIMS');
  const fingerprint = deviceFingerprint(devicePublicKeyPem);
  return Buffer.from(['NKTOUCH-PROOF-V1', challenge, action, licenseId, fingerprint].join('\n'), 'utf8');
}

// Test/client helper. On iOS sign the same proofBytes with P-256 Secure Enclave key.
export function signProof(claims, privateKeyPem) {
  const key = createPrivateKey(privateKeyPem);
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new LeaseError('INVALID_DEVICE_KEY');
  return sign('sha256', proofBytes(claims), { key, dsaEncoding: 'der' }).toString('base64url');
}

// The API MUST additionally consume a stored challenge atomically and check license status.
export function verifyProof(claims, signature) {
  if (typeof signature !== 'string' || signature.length > 256 || !/^[A-Za-z0-9_-]+$/.test(signature)) return false;
  try {
    const key = createPublicKey(claims.devicePublicKeyPem);
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') return false;
    const binary = Buffer.from(signature, 'base64url');
    if (binary.toString('base64url') !== signature) return false;
    return verify('sha256', proofBytes(claims), key, binary);
  } catch { return false; }
}
