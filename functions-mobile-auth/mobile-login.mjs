const socialProviders = new Set(['google.com', 'apple.com']);

export async function exchangeMobileLogin({
  method, authorization, purpose, provider, verify, issue, now = Date.now(),
}) {
  const error = (status, code) => ({status, body: {error: code}});
  if (method !== 'POST') return error(405, 'method-not-allowed');
  if (!socialProviders.has(provider) ||
      !['sign-in', 'start-link', 'finish-link'].includes(purpose)) {
    return error(400, 'invalid-request');
  }
  const token = /^Bearer ([a-zA-Z0-9_.-]{1,8192})$/.exec(authorization ?? '')?.[1];
  if (!token) return error(401, 'authentication-required');

  let identity;
  try {
    identity = await verify(token);
  } catch {
    return error(401, 'authentication-required');
  }
  const age = now - identity.auth_time * 1000;
  if (!identity.uid || !Number.isFinite(age) || age < -30_000 || age > 300_000) {
    return error(401, 'recent-login-required');
  }
  const methodUsed = identity.firebase?.sign_in_provider;
  const linkedProvider = identity.firebase?.identities?.[provider];
  const allowed = purpose === 'start-link'
    ? methodUsed === 'password'
    : purpose === 'finish-link'
      ? methodUsed === 'custom' && Array.isArray(linkedProvider) && linkedProvider.length > 0
      : methodUsed === provider;
  if (!allowed) return error(403, 'provider-required');

  try {
    return {status: 200, body: {token: await issue(identity.uid)}};
  } catch {
    return error(503, 'token-unavailable');
  }
}
