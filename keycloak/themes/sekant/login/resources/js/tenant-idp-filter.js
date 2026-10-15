// Shows only the identity providers that belong to the organization the user is
// signing in to.
//
// Keycloak lists every realm identity provider on its login page, so without
// this a tenant would also see the root organization's providers and every
// other tenant's OIDC buttons. Identity providers are named
// `t_<identifier>_<provider>` for a tenant organization and keep the bare
// provider name (`google`, `microsoft`, `okta`) for the root organization.
//
// The console passes the organization to Keycloak as the standard `kc_org`
// query parameter, and it also prefills the username with the tenant principal
// (`t_<identifier>_<username>`). Either source identifies the organization, so
// the filter still works when a flow drops the query parameter. When the
// organization cannot be determined, nothing is hidden, which keeps the plain
// realm login unchanged.
(function () {
  'use strict';

  // Mirrors ROOT_ORG_IDENTIFIER in backend/src/lib/tenantIdentity.js.
  var ROOT_IDENTIFIER = 'sekant';
  // Any tenant-scoped provider alias, e.g. t_acme_google.
  var TENANT_PROVIDER_PATTERN = /^t_[a-z0-9]+_/i;

  function normalizeIdentifier(value) {
    var normalized = String(value == null ? '' : value).trim().toLowerCase();
    if (!normalized) return '';
    return normalized.indexOf('o_') === 0 ? normalized.slice(2) : normalized;
  }

  function identifierFromQuery() {
    try {
      return normalizeIdentifier(new URLSearchParams(window.location.search).get('kc_org'));
    } catch (error) {
      return '';
    }
  }

  function usernameFieldValue() {
    var editable = document.getElementById('username');
    if (editable && String(editable.value || '').trim()) return String(editable.value);
    var attempted = document.getElementById('kc-attempted-username');
    return attempted ? String(attempted.value || '') : '';
  }

  function identifierFromUsername() {
    var match = /^t_([a-z0-9]+)_/i.exec(usernameFieldValue());
    return match ? match[1].toLowerCase() : '';
  }

  function providerAlias(link) {
    var match = /\/broker\/([^/?#]+)/i.exec(String(link.getAttribute('href') || ''));
    return match ? decodeURIComponent(match[1]).toLowerCase() : '';
  }

  function belongsToOrganization(alias, identifier) {
    if (!alias) return true;
    if (identifier === ROOT_IDENTIFIER) {
      // The root organization owns the providers without a tenant prefix.
      return !TENANT_PROVIDER_PATTERN.test(alias);
    }
    return alias.indexOf('t_' + identifier + '_') === 0;
  }

  function hideElement(element) {
    if (element) element.style.display = 'none';
  }

  function applyFilter() {
    var identifier = identifierFromQuery() || identifierFromUsername();
    if (!identifier) return;

    var container = document.getElementById('kc-social-providers');
    if (!container) return;

    var links = container.querySelectorAll('a[href]');
    var visible = 0;
    for (var index = 0; index < links.length; index += 1) {
      var link = links[index];
      if (belongsToOrganization(providerAlias(link), identifier)) {
        visible += 1;
        continue;
      }
      hideElement(link.closest('li') || link);
    }

    // Nothing left for this organization: remove the whole provider block so an
    // empty section and its heading are not shown.
    if (visible === 0) {
      hideElement(container);
      var heading = container.previousElementSibling;
      if (heading && /sign in with/i.test(heading.textContent || '')) {
        hideElement(heading);
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyFilter);
  } else {
    applyFilter();
  }
})();
