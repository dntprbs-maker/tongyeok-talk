const testRoles = ['korean', 'mongolian'];

export async function qaAccess({method, authorization, purpose, target, config, verify, issue}) {
  const error = (status, code) => ({status, body: {error: code}});
  if (method !== 'POST') return error(405, 'method-not-allowed');
  const {operator, korean, mongolian} = config;
  if (![operator, korean, mongolian].every(Boolean) || new Set([operator, korean, mongolian]).size !== 3) {
    return error(404, 'qa-not-configured');
  }
  const token = /^Bearer ([a-zA-Z0-9_.-]{1,8192})$/.exec(authorization ?? '')?.[1];
  if (!token) return error(401, 'authentication-required');

  let identity;
  try {
    identity = await verify(token);
  } catch {
    return error(401, 'authentication-required');
  }
  const provider = identity.firebase?.sign_in_provider;
  const googleIds = identity.firebase?.identities?.['google.com'];
  const isOperator = identity.uid === operator && identity.email_verified === true &&
    Array.isArray(googleIds) && googleIds.length > 0 && ['google.com', 'custom'].includes(provider);
  const role = isOperator ? 'administrator' : testRoles.find(testRole =>
    config[testRole] === identity.uid && provider === 'custom' && identity.tongyeokQaRole === testRole);
  if (!role) return error(403, 'qa-not-authorized');
  if (purpose === 'qa-access') return {status: 200, body: {role}};
  if (purpose !== 'qa-switch' || !testRoles.includes(target)) return error(400, 'invalid-qa-target');

  try {
    const userToken = await issue(config[target], {tongyeokQaRole: target});
    return {status: 200, body: {token: userToken}};
  } catch {
    return error(503, 'token-unavailable');
  }
}
