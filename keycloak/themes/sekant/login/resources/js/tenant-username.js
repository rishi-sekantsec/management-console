// Keeps the internal tenant prefix out of the Keycloak sign-in page.
//
// Tenant users are stored in Keycloak as `t_<identifier>_<username>`. The console
// hands off to Keycloak without a username, so the end user types only their own
// username here; the prefix for the organization they signed in to is prepended
// on submit and the user never sees it.
//
// The organization is carried in the standard `kc_org` query parameter that the
// console sends and Keycloak keeps on the sign-in page. When it is missing, the
// prefix is taken from a prefilled principal if one is present (for example when
// a login hint was used).
//
// Keycloak renders the resolved identity in two different ways depending on the
// flow, so both are handled:
//   - `kc-attempted-username` is a readonly field shown when Keycloak already
//     resolved the account from a hint. It is never submitted, so rewriting it is
//     display only.
//   - `username` is the editable field. Its submitted value needs the prefix.
//
// The script runs on every login-theme page, so it does nothing unless an
// organization context or a prefixed principal is actually present.
(function () {
  'use strict';

  // Mirrors ROOT_ORG_IDENTIFIER in backend/src/lib/tenantIdentity.js. Root
  // organization users are stored without a tenant prefix, so nothing may be
  // prepended for them (`admin` stays `admin`).
  var ROOT_IDENTIFIER = 'sekant';
  // Mirrors the backend tenant prefix convention: t_<identifier>_<username>.
  var PREFIX_PATTERN = /^(t_[a-z0-9]+)_(.+)$/i;

  function splitPrincipal(value) {
    var match = PREFIX_PATTERN.exec(String(value == null ? '' : value));
    if (!match) return null;
    return { prefix: match[1] + '_', username: match[2] };
  }

  // Organization the user signed in to, from the `kc_org` query parameter
  // (`o_<identifier>`). Returns a bare identifier or ''.
  function organizationIdentifier() {
    try {
      var raw = new URLSearchParams(window.location.search).get('kc_org') || '';
      var normalized = String(raw).trim().toLowerCase();
      if (!normalized) return '';
      return normalized.indexOf('o_') === 0 ? normalized.slice(2) : normalized;
    } catch (error) {
      return '';
    }
  }

  function hideResolvedUsername() {
    var attempted = document.getElementById('kc-attempted-username');
    if (!attempted) return;
    var principal = splitPrincipal(attempted.value);
    if (!principal) return;
    attempted.value = principal.username;
  }

  function prepareUsernamePrefix() {
    var input = document.getElementById('username');
    if (!input || !input.form) return;

    var principal = splitPrincipal(input.value);
    var prefix = principal ? principal.prefix : '';
    if (!prefix) {
      var identifier = organizationIdentifier();
      // The root organization (`o_sekant`) has no tenant prefix at all, so its
      // sign-in page must submit the bare username.
      if (identifier && identifier !== ROOT_IDENTIFIER) prefix = 't_' + identifier + '_';
    }

    if (principal) {
      // A prefilled principal is shown to the user without the internal prefix.
      input.value = principal.username;
    }

    if (!prefix) return;

    input.form.addEventListener('submit', function () {
      var current = String(input.value == null ? '' : input.value);
      if (!current) return;
      // Re-apply the prefix whether the user typed a bare username or the field
      // still holds a resolved principal.
      var typed = splitPrincipal(current);
      input.value = prefix + (typed ? typed.username : current);
    });
  }

  function init() {
    hideResolvedUsername();
    prepareUsernamePrefix();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
