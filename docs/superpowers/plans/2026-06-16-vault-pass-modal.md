# `{{pass}}` Card Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking a `{{pass(ID)}}` link opens the password card in a modal overlay on the same page instead of navigating to the card page.

**Architecture:** Add a session-auth `keys#card` endpoint that renders the existing `_detail` partial (layout-less, with a `whitelisted?` guard). The macro keeps its `href` (no-JS fallback) and gains a `data-card-url`. `vault.js` intercepts clicks, fetches the card, and shows it in a reusable overlay; reveal/copy already work via document-delegated handlers. `vault.css` styles the overlay.

**Tech Stack:** Redmine 6.1 plugin (Rails 7.2, Ruby 3.3), Minitest (`Redmine::ControllerTest`), jQuery, Font Awesome.

---

## File structure

- Modify `config/routes.rb` — add the `card` member route.
- Modify `app/controllers/keys_controller.rb` — add `card` action + `:card` to `find_key`.
- Modify `init.rb` — add `:card` to the `view_keys` permission; add `data-card-url` to the macro link; bump version to `0.8.1`.
- Modify `assets/javascripts/vault.js` — card overlay open/close + click handler.
- Modify `assets/stylesheets/vault.css` — overlay styles.
- Modify `CHANGELOG.md` — `0.8.1` entry.
- Create `test/functional/keys_card_test.rb` — functional tests for `card`.

---

## Task 1: `keys#card` endpoint (TDD)

**Files:**
- Create: `test/functional/keys_card_test.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/keys_controller.rb`
- Modify: `init.rb` (permission only)

- [ ] **Step 1: Write the failing test**

Create `test/functional/keys_card_test.rb`:

```ruby
require File.expand_path('../../test_helper', __FILE__)

class KeysCardTest < Redmine::ControllerTest
  tests KeysController
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys)
    @key = Vault::Key.create!(project: @project, name: 'DB root', type: 'Vault::Password',
                              login: 'root', body: 's3cret', whitelist: '')
  end

  def test_card_renders_detail_partial_for_whitelisted
    @request.session[:user_id] = 1 # admin sees all
    get :card, params: { project_id: @project.identifier, id: @key.id }
    assert_response :success
    assert_select 'div.vault-card'
    assert_match 'root', response.body          # login shown
    refute_match(/<body|id="main-menu"/, response.body) # no layout
  end

  def test_card_forbidden_for_non_whitelisted
    Role.find(1).add_permission!(:view_keys, :whitelist_keys)
    @key.update_column(:whitelist, '99')        # group/user 99, not user 2
    @request.session[:user_id] = 2              # jsmith, non-admin, member of project 1
    get :card, params: { project_id: @project.identifier, id: @key.id }
    assert_response :forbidden
  end

  def test_card_missing_key_404
    @request.session[:user_id] = 1
    get :card, params: { project_id: @project.identifier, id: 999999 }
    assert_response :missing
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run (inside a Redmine checkout with the plugin):
`bin/rails redmine:plugins:test NAME=vault TEST=plugins/vault/test/functional/keys_card_test.rb RAILS_ENV=test`
Expected: FAIL — no route matches `card` / `NoMethodError: undefined method 'card'`.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `resources :projects do` block, add next to the `copy` route:

```ruby
  get '/keys/:id/card', to: 'keys#card', as: 'card_key'
```

- [ ] **Step 4: Add the action + find_key + permission**

In `app/controllers/keys_controller.rb`, extend the `find_key` filter to include `:card`:

```ruby
  before_action :find_key, only: [ :show, :edit, :update, :destroy, :copy, :card ]
```

Add the action (place it right after `show`):

```ruby
  def card
    unless @key.whitelisted?(User, @project)
      head :forbidden and return
    end
    @key.decrypt!
    render partial: 'keys/detail', locals: { key: @key }, layout: false
  end
```

In `init.rb`, add `:card` to the `view_keys` permission action list:

```ruby
      permission :view_keys, keys: [ :index, :edit, :show, :context_menu, :picker, :card ]
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails redmine:plugins:test NAME=vault TEST=plugins/vault/test/functional/keys_card_test.rb RAILS_ENV=test`
Expected: PASS (3 runs, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/keys_controller.rb init.rb test/functional/keys_card_test.rb
git commit -m "feat: keys#card endpoint renders the password card partial (whitelist-guarded)"
```

---

## Task 2: Macro emits `data-card-url`

**Files:**
- Modify: `init.rb` (the `{{pass}}` macro block)

- [ ] **Step 1: Add the data attribute to the macro link**

In `init.rb`, in the `macro :pass` block, replace the `:ok` branch's `link_to` with one that adds `data-card-url`:

```ruby
    when :ok
      key = res[:key]
      lock + link_to(label || key.name,
                     url_for(controller: 'keys', action: 'show',
                             project_id: key.project, id: key.id, only_path: true),
                     class: 'vault-pass-link',
                     data: { card_url: url_for(controller: 'keys', action: 'card',
                                               project_id: key.project, id: key.id, only_path: true) })
```

- [ ] **Step 2: Boot-check (the macro is parsed at boot)**

Run: `bin/rails runner 'puts "ok"' RAILS_ENV=production`
Expected: prints `ok` with no `SyntaxError`/`NameError`.

- [ ] **Step 3: Commit**

```bash
git add init.rb
git commit -m "feat: {{pass}} link carries data-card-url for the modal"
```

---

## Task 3: `vault.js` — open the card in a modal

**Files:**
- Modify: `assets/javascripts/vault.js`

- [ ] **Step 1: Add the card-modal functions + click handler**

Append to `assets/javascripts/vault.js`:

```javascript
// ---- {{pass}} card modal: open the password card in an overlay (no navigation) ----
function vaultCloseCard() {
  var ov = document.getElementById("vault-card-overlay");
  if (ov) { ov.parentNode.removeChild(ov); }
}

function vaultOpenCard(url, title) {
  vaultCloseCard();
  var ov = document.createElement("div");
  ov.id = "vault-card-overlay";
  ov.className = "vault-card-overlay";
  ov.setAttribute("onclick", "if(event.target===this)vaultCloseCard();");

  var box = document.createElement("div");
  box.className = "vault-card-modal";
  box.innerHTML =
    "<div class='vault-card-close' onclick='vaultCloseCard();'>&#x2715;</div>" +
    "<h3 class='vault-card-mtitle'><i class='fa fa-lock fa-fw'></i> " +
      jQuery("<span>").text(title || "").html() + "</h3>" +
    "<div class='vault-card-mbody'>" + vaultI18n("loading", "Loading…") + "</div>";
  ov.appendChild(box);
  document.body.appendChild(ov);

  jQuery.ajax({ url: url, dataType: "html" })
    .done(function(html) { box.querySelector(".vault-card-mbody").innerHTML = html; })
    .fail(function() { window.location = url.replace(/\/card(\?.*)?$/, ""); });
}

// Click a {{pass}} link → open the card modal instead of navigating.
// data-card-url absent (older render / no JS) → default navigation kept.
jQuery(document).on("click", ".vault-pass-link", function(e) {
  var url = jQuery(this).data("card-url");
  if (!url) { return; }
  e.preventDefault();
  vaultOpenCard(url, jQuery(this).text());
});

jQuery(document).on("keydown", function(e) {
  if (e.key === "Escape" || e.keyCode === 27) { vaultCloseCard(); }
});
```

- [ ] **Step 2: Manual verify (after deploy, Task 6)**

On a page containing `{{pass(ID)}}` (e.g. eietlimps wiki Test_email), click the link:
Expected: an overlay opens with the card; the password is masked with working eye (reveal) and clipboard (copy) icons; ×, ESC, and click-outside all close it; the page never navigates.

- [ ] **Step 3: Commit**

```bash
git add assets/javascripts/vault.js
git commit -m "feat: {{pass}} link opens the card in a modal overlay"
```

---

## Task 4: `vault.css` — overlay styles

**Files:**
- Modify: `assets/stylesheets/vault.css`

- [ ] **Step 1: Append the overlay styles**

Append to `assets/stylesheets/vault.css`:

```css
/* {{pass}} card modal */
.vault-card-overlay {
  position: fixed; inset: 0; background: rgba(0,0,0,0.6);
  z-index: 10000; display: flex; justify-content: center;
  align-items: flex-start; padding-top: 8vh;
}
.vault-card-modal {
  position: relative; background: #fff; border-radius: 8px;
  padding: 16px 20px; min-width: 340px; max-width: 90vw;
  max-height: 80vh; overflow: auto; box-shadow: 0 8px 30px rgba(0,0,0,0.5);
}
.vault-card-modal .vault-card { box-shadow: none; border: none; padding: 0; }
.vault-card-close {
  position: absolute; top: -12px; right: -12px; width: 28px; height: 28px;
  line-height: 28px; text-align: center; font-weight: bold; color: #fff;
  background: #e74c3c; border-radius: 50%; cursor: pointer;
  box-shadow: 0 2px 6px rgba(0,0,0,0.3);
}
.vault-card-mtitle { margin: 0 0 10px; }
```

- [ ] **Step 2: Commit**

```bash
git add assets/stylesheets/vault.css
git commit -m "style: {{pass}} card modal overlay"
```

---

## Task 5: Version bump + CHANGELOG (mandatory)

**Files:**
- Modify: `init.rb` (version)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump the version**

In `init.rb`, change `version '0.8.0'` → `version '0.8.1'`.

- [ ] **Step 2: Add the CHANGELOG entry**

Prepend to `CHANGELOG.md`:

```markdown
## Version: 0.8.1 (16.06.2026)
### Features
- The `{{pass(ID)}}` link now opens the password **card in a modal overlay** on the
  same page (masked body with reveal/copy, login, url, tags, attachments, comment)
  instead of navigating to the card page — so reading a password from a wiki article
  or issue no longer loses your place. New session-auth `keys#card` endpoint renders
  the existing `_detail` partial, guarded by `whitelisted?` (403 otherwise). The
  macro keeps its `href` as a no-JS fallback. ESC / × / click-outside close the modal.
```

- [ ] **Step 3: Commit**

```bash
git add init.rb CHANGELOG.md
git commit -m "chore: bump version to 0.8.1 (card modal)"
```

---

## Task 6: Full test run + deploy to the 3 Redmines

**Files:** none (ops)

- [ ] **Step 1: Run the whole plugin suite**

Run: `bin/rails redmine:plugins:test NAME=vault RAILS_ENV=test`
Expected: all green (existing tests + the 3 new card tests).

- [ ] **Step 2: Push origin (covers all 3 hosts)**

```bash
git push origin redmine-6.1
```

- [ ] **Step 3: Deploy per host** (red.half `10.0.53.6`, vs-com `10.0.50.236`, volia `192.168.84.118`), `sudo ssh -p 5022 root@<ip>`:

```bash
cd <redmine_root>
git -C plugins/vault fetch origin redmine-6.1 && git -C plugins/vault reset --hard origin/redmine-6.1
sudo -u <appowner> RAILS_ENV=production bin/rails runner 'puts "boot-ok"'   # boot-check BEFORE precompile
sudo -u <appowner> RAILS_ENV=production bin/rails assets:precompile          # vault.js + vault.css changed — MANDATORY
touch tmp/restart.txt
```
(No new migration in this release.)

- [ ] **Step 4: Verify the served asset carries the new code**

Run: `curl -s https://<host>/assets/plugin_assets/vault/vault-<digest>.js | grep vaultOpenCard`
Expected: the function is present (identical source → identical digest across all 3 hosts).

- [ ] **Step 5: Manual smoke (volia)**

Open `https://redmine.voliasoftware.com/projects/eietlimps/wiki/Test_email`, click the 🔒 link → modal opens with the card, reveal + copy work, ESC/×/outside close, no navigation.

---

## Self-review notes

- **Spec coverage:** route ✓ (T1), controller+guard ✓ (T1), `:card` permission ✓ (T1), macro data-url ✓ (T2), vault.js modal ✓ (T3), vault.css ✓ (T4), tests ✓ (T1), version+CHANGELOG ✓ (T5), deploy+precompile ✓ (T6). Fallback (href) preserved ✓ (T2 keeps href).
- **No placeholders:** all code shown inline.
- **Naming consistency:** `vaultOpenCard`/`vaultCloseCard`, `.vault-card-overlay`/`.vault-card-modal`/`.vault-card-mbody`/`.vault-card-mtitle`, route `card_key`, action `card` — used consistently across T1–T6.
