# Design: `{{pass}}` opens the password card in a modal (v0.8.1)

## Problem

The `{{pass(ID)}}` macro (v0.7.0) renders a link that **navigates** to the full
password page (`/projects/<p>/keys/<id>`). From a wiki article or an issue that is
awkward: the card page's "Back" goes to the passwords **list**, not to the page you
came from, so the reader loses their place. We want to view the password **without
leaving the current page**.

## Goal

Clicking a `{{pass}}` link opens the password **card in a modal overlay** on the
same page (masked body with reveal/copy, login, url, tags, attachments, comment).
Closing the modal leaves the reader exactly where they were. No navigation.

## Approach (chosen)

Progressive enhancement over the existing link — reuse the card partial and the
existing overlay/delegation patterns already in `vault.js`.

### Components

1. **Route** — `GET /projects/:project_id/keys/:id/card` (`as: card_key`).
2. **Controller** — `Keys#card`: enforce `whitelisted?(User, @project)` (→ `403`
   otherwise, same guard as `show`), then `render partial: 'keys/detail',
   locals: { key: @key }, layout: false`. Decrypt first (`@key.decrypt!`). Add
   `:card` to the `view_keys` permission action list in `init.rb`. Session auth
   (logged-in AJAX) — no `accept_api_auth` needed.
3. **Macro** (`init.rb`) — keep the existing `<a class="vault-pass-link"
   href="…/keys/<id>">name</a>` (the href stays as the **no-JS fallback**) and add
   `data-card-url="<card path>"` so the JS knows where to fetch the card.
4. **`vault.js`** — delegated `click` on `.vault-pass-link`: `preventDefault`,
   fetch `data-card-url` HTML, inject into a card modal (overlay + box + close ×,
   title = link text), show. Reuse the overlay style; ESC / click-outside / × close.
   Reveal (`.vault-reveal`) and copy (`[data-clipboard-target]`) already use
   **document-delegated** handlers, so they work inside the injected card unchanged.
5. **CSS** (`vault.css`) — a `.vault-card-overlay` / `.vault-card-modal` block
   (mirrors the existing picker overlay).

### Security / permissions

The macro only renders a real link for users on the key's whitelist (resolver
returns `:ok`); others get the neutral "(no access)" text with no link. The `card`
action **re-checks** `whitelisted?` server-side (defense in depth) and 403s
otherwise, so the endpoint can't be used to read a card the user can't access.

### Fallback

JS disabled / fetch fails → the link's `href` still navigates to the full card
page exactly as today. Nothing regresses.

## Out of scope

- The "Back button returns to referrer" alternative (variant B) — rejected: still a
  navigation round-trip, `document.referrer` unreliable.
- Editing/among-card actions in the modal (edit/delete) — the modal is read-only;
  full page remains for management.

## Testing

- **Controller test** (`test/functional`): `card` returns the partial (200, contains
  login/body markup) for a whitelisted user; `403` for a non-whitelisted user with
  `whitelist_keys`; `404` for a missing key. Follow existing `keys_controller` test
  style.
- **Manual/deploy verify**: on a real page, click a `{{pass}}` link → modal opens
  with the card; reveal + copy work; ESC/×/outside close; no navigation; no-JS link
  still works.

## Deploy

Same recipe as 0.7.0/0.8.0 across all 3 Redmines (red.half, vs-com, volia): git
reset → `redmine:plugins:migrate` (no new migration here) → **`assets:precompile`**
(vault.js + vault.css changed — mandatory, else the stale digest is served) →
`touch tmp/restart.txt`. Boot-check with `bin/rails runner` before precompile.

**Versioning (mandatory for every plugin change):** bump the version in `init.rb`
(→ **0.8.1**) AND add a `CHANGELOG.md` entry that states exactly what changed
(feature: `{{pass}}` opens the card in a modal instead of navigating; new
`keys#card` endpoint; vault.js modal; vault.css overlay). No silent edits.
