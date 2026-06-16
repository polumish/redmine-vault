# Vault Cosmetics + `{{pass}}` Linking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Redmine Vault plugin a Redmine-native, compact look for the Passwords list and single-password detail, plus a permission-aware `{{pass(ID)}}` wiki macro with an editor toolbar button + project-scoped picker.

**Architecture:** Pure-Ruby macro resolver (`Vault::PasswordLink`) unit-tested in isolation, wired to a Redmine wiki macro. A lightweight session-authed JSON endpoint (`keys#picker`) feeds a jsToolBar button + modal added by the already-injected `vault.js`. List/detail views are reworked to Redmine-native markup; the tangled list-row vs detail partials are separated. CSS lives in the 29-line `vault.css`.

**Tech Stack:** Redmine 6.1 plugin (Ruby/Rails 7.2, ERB), jQuery + jsToolBar (textile), Font-Awesome (bundled), MariaDB. Tests: Redmine's `ActiveSupport::TestCase` / `Redmine::ControllerTest`.

**Spec:** `docs/superpowers/specs/2026-06-16-vault-cosmetics-and-linking-design.md`

---

## File structure

**Create:**
- `lib/vault/password_link.rb` — pure resolver for `{{pass(id)}}` (testable).
- `lib/vault/macros.rb` — registers the `pass` wiki macro using the resolver.
- `app/views/keys/_detail.html.erb` — single-password detail card (replaces bare `render @key`).
- `test/unit/vault_password_link_test.rb` — resolver unit tests.
- `test/functional/keys_picker_test.rb` — picker endpoint test.

**Modify:**
- `init.rb` — require resolver+macros; add `:picker` to `view_keys`; emit `window.VAULT_I18N`; bump version `0.7.0`.
- `config/routes.rb` — add `keys/picker` route **before** `resources :keys`.
- `app/controllers/keys_controller.rb` — add `picker` action.
- `app/views/keys/index.html.erb` — toolbar out of `<h2>`; aligned Update/Clear.
- `app/views/keys/show.html.erb` — contextual actions + render `_detail`.
- `app/views/shared/_key_fields.html.erb` — show muted `#id` next to name.
- `app/views/shared/_key_actions.html.erb` — add `⧉ link` (copy macro) action.
- `app/views/keys/_form.html.erb` — wrap attachments section as a tabular row (layout fix).
- `assets/javascripts/vault.js` — toolbar button, picker modal, reveal toggle, copy-link, broaden copy handler.
- `assets/stylesheets/vault.css` — card, chips, toolbar, picker modal, attachments-fix styles.
- `config/locales/en.yml`, `config/locales/ru.yml` — new labels.

---

## Task 0: Make the test harness able to load `test_helper`

The colima `docker cp` harness can't `require test_helper` because `capybara-screenshot` is missing (known). Install it in the test container so unit/functional tests load.

- [ ] **Step 1: In the Redmine-6.1 test container, install the missing gems**

Run (inside the harness container, RAILS_ENV=test):
```bash
gem install capybara capybara-screenshot --no-document
```
Expected: gems install; `bin/rails runner -e test "require 'capybara-screenshot'"` exits 0.

- [ ] **Step 2: Smoke-load test_helper**

Run: `RAILS_ENV=test bin/rails runner "require File.expand_path('test/test_helper', Dir.pwd)" 2>&1 | tail -3`
Expected: no LoadError about capybara-screenshot.

---

## Task 1: i18n labels

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`

- [ ] **Step 1: Add labels to `en.yml`** under the existing `key:` map

In `key.btn` add:
```yaml
      copy_link: "Copy link macro"
      show: "Show"
      hide: "Hide"
```
In `key.attr` add:
```yaml
      id: "ID"
```
Add new sub-maps under `key:` (same indentation as `attr:`):
```yaml
    macro:
      no_access: "(no access)"
      not_found: "(not found)"
    toolbar:
      insert_pass: "Insert password link"
    picker:
      title: "Insert password link"
      search: "Search…"
      empty: "No passwords available"
```

- [ ] **Step 2: Mirror in `ru.yml`** under `key:`

`key.btn`:
```yaml
      copy_link: "Скопировать макрос-ссылку"
      show: "Показать"
      hide: "Скрыть"
```
`key.attr`:
```yaml
      id: "ID"
```
New sub-maps under `key:`:
```yaml
    macro:
      no_access: "(нет доступа)"
      not_found: "(не найдено)"
    toolbar:
      insert_pass: "Вставить ссылку на пароль"
    picker:
      title: "Вставить ссылку на пароль"
      search: "Поиск…"
      empty: "Нет доступных паролей"
```

- [ ] **Step 3: Verify YAML parses**

Run: `ruby -ryaml -e 'YAML.load_file("config/locales/en.yml"); YAML.load_file("config/locales/ru.yml"); puts "ok"'`
Expected: `ok`

- [ ] **Step 4: Commit**
```bash
git add config/locales/en.yml config/locales/ru.yml
git commit -m "i18n: labels for pass macro, picker, copy-link, reveal"
```

---

## Task 2: `Vault::PasswordLink` resolver (TDD)

**Files:**
- Create: `lib/vault/password_link.rb`
- Test: `test/unit/vault_password_link_test.rb`

- [ ] **Step 1: Write the failing test**

`test/unit/vault_password_link_test.rb`:
```ruby
require File.expand_path('../../test_helper', __FILE__)

class VaultPasswordLinkTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys, :whitelist_keys)
  end

  def test_not_found
    User.current = User.find(1)
    assert_equal :not_found, Vault::PasswordLink.resolve(99999)[:state]
  end

  def test_ok_for_admin
    User.current = User.find(1) # admin -> always whitelisted
    key = Vault::Key.create!(project: @project, name: 'k-ok', type: 'Vault::Password', whitelist: '')
    res = Vault::PasswordLink.resolve(key.id)
    assert_equal :ok, res[:state]
    assert_equal key.id, res[:key].id
  end

  def test_no_access_when_not_whitelisted
    User.current = User.find(2) # jsmith, member of project 1, has whitelist_keys via role
    key = Vault::Key.create!(project: @project, name: 'k-na', type: 'Vault::Password', whitelist: '99999')
    assert_equal :no_access, Vault::PasswordLink.resolve(key.id)[:state]
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `RAILS_ENV=test bin/rails test test/unit/vault_password_link_test.rb 2>&1 | tail -15`
Expected: FAIL — `uninitialized constant Vault::PasswordLink`.

- [ ] **Step 3: Implement the resolver**

`lib/vault/password_link.rb`:
```ruby
module Vault
  # Pure resolution for the {{pass(id)}} wiki macro. Kept separate from the macro/view
  # layer so it can be unit-tested and later re-pointed at other backends (e.g. Vaultwarden).
  module PasswordLink
    # @return [Hash] { state: :ok, key: <Vault::Key> } | { state: :no_access } | { state: :not_found }
    def self.resolve(id)
      key = Vault::Key.find_by(id: id)
      return { state: :not_found } if key.nil?
      if User.current.allowed_to?(:view_keys, key.project) &&
         key.whitelisted?(User, key.project)
        { state: :ok, key: key }
      else
        { state: :no_access }
      end
    end
  end
end
```

- [ ] **Step 4: Require it from `init.rb`** (after the vendor requires, before the plugin register block)

Add to `init.rb` after line `require File.expand_path('vendor/project_patch', __dir__)`:
```ruby
require File.expand_path('lib/vault/password_link', __dir__)
```

- [ ] **Step 5: Run tests, verify they pass**

Run: `RAILS_ENV=test bin/rails test test/unit/vault_password_link_test.rb 2>&1 | tail -15`
Expected: PASS (3 runs, 0 failures).

- [ ] **Step 6: Commit**
```bash
git add lib/vault/password_link.rb test/unit/vault_password_link_test.rb init.rb
git commit -m "feat: Vault::PasswordLink resolver for {{pass}} macro"
```

---

## Task 3: Register the `{{pass}}` macro

**Files:**
- Create: `lib/vault/macros.rb`
- Modify: `init.rb`

- [ ] **Step 1: Implement the macro**

`lib/vault/macros.rb`:
```ruby
Redmine::WikiFormatting::Macros.register do
  desc "Link to a Vault password.\n\n{{pass(42)}}\n{{pass(42, \"custom label\")}}"
  macro :pass do |obj, args|
    id = args[0].to_s.strip
    label = args[1].to_s.strip.gsub(/\A["']|["']\z/, '').presence
    res = Vault::PasswordLink.resolve(id)
    lock = content_tag(:i, ''.html_safe, class: 'fa fa-lock fa-fw')
    case res[:state]
    when :ok
      key = res[:key]
      lock + link_to(label || key.name,
                     url_for(controller: 'keys', action: 'show',
                             project_id: key.project, id: key.id, only_path: true),
                     class: 'vault-pass-link')
    when :no_access
      content_tag(:span, lock + ' '.html_safe + l('key.macro.no_access'), class: 'vault-pass-noaccess')
    else
      content_tag(:span, lock + ' '.html_safe + l('key.macro.not_found'), class: 'vault-pass-notfound')
    end
  end
end
```

- [ ] **Step 2: Require it from `init.rb`** (right after the password_link require)
```ruby
require File.expand_path('lib/vault/macros', __dir__)
```

- [ ] **Step 3: Verify macro is registered (boots clean)**

Run: `RAILS_ENV=production bin/rails runner "puts Redmine::WikiFormatting::Macros.available_macros.key?(:pass)"`
Expected: `true`

- [ ] **Step 4: Commit**
```bash
git add lib/vault/macros.rb init.rb
git commit -m "feat: register {{pass(id)}} wiki macro (permission-aware)"
```

---

## Task 4: Picker endpoint (TDD)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/keys_controller.rb`
- Modify: `init.rb` (permission)
- Test: `test/functional/keys_picker_test.rb`

- [ ] **Step 1: Write the failing test**

`test/functional/keys_picker_test.rb`:
```ruby
require File.expand_path('../../test_helper', __FILE__)

class KeysPickerTest < Redmine::ControllerTest
  tests KeysController
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys)
    @request.session[:user_id] = 1 # admin sees all
    Vault::Key.create!(project: @project, name: 'Zeta',  type: 'Vault::Password', whitelist: '')
    Vault::Key.create!(project: @project, name: 'Alpha', type: 'Vault::Password', whitelist: '')
  end

  def test_picker_returns_sorted_id_name_only
    get :picker, params: { project_id: @project.identifier }
    assert_response :success
    data = JSON.parse(response.body)
    assert data.is_a?(Array)
    assert_equal %w[Alpha Zeta], data.map { |h| h['name'] }
    assert_equal %w[id name], data.first.keys.sort
    refute data.first.key?('body')
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `RAILS_ENV=test bin/rails test test/functional/keys_picker_test.rb 2>&1 | tail -15`
Expected: FAIL — no route / unknown action `picker`.

- [ ] **Step 3: Add the route** in `config/routes.rb`, **above** `resources :keys` (so `picker` isn't captured as `:id`)

Change the `resources :projects do` block so its first lines read:
```ruby
resources :projects do
  match '/keys/context_menu', to: 'keys#context_menu', as: 'keys_context_menus', via: [:get, :post]
  get '/keys/picker', to: 'keys#picker', as: 'keys_picker'
  resources :keys
```

- [ ] **Step 4: Add the action** in `app/controllers/keys_controller.rb` (in the public section, e.g. after `def index ... end`)
```ruby
  def picker
    keys = @project.keys.order(:name).select { |k| k.whitelisted?(User, @project) }
    render json: keys.map { |k| { id: k.id, name: k.name } }
  end
```

- [ ] **Step 5: Grant the permission** — in `init.rb`, add `:picker` to `view_keys`:
```ruby
    permission :view_keys, keys: [ :index, :edit, :show, :context_menu, :picker ]
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `RAILS_ENV=test bin/rails test test/functional/keys_picker_test.rb 2>&1 | tail -15`
Expected: PASS (1 run, 0 failures).

- [ ] **Step 7: Commit**
```bash
git add config/routes.rb app/controllers/keys_controller.rb init.rb test/functional/keys_picker_test.rb
git commit -m "feat: keys#picker JSON endpoint (id+name of accessible keys)"
```

---

## Task 5: VAULT_I18N + JS (toolbar button, picker, reveal, copy-link, broaden copy)

**Files:**
- Modify: `init.rb` (emit `window.VAULT_I18N`)
- Modify: `assets/javascripts/vault.js`

- [ ] **Step 1: Emit localized strings for JS** — replace the `VaultViewHook#view_layouts_base_html_head` body in `init.rb` with:
```ruby
  def view_layouts_base_html_head(context = {})
    i18n = {
      insert_pass:   l('key.toolbar.insert_pass'),
      picker_title:  l('key.picker.title'),
      picker_search: l('key.picker.search'),
      picker_empty:  l('key.picker.empty'),
      copied:        l('key.btn.clipboard')
    }
    stylesheet_link_tag('vault', plugin: 'vault') +
      javascript_include_tag('vault', plugin: 'vault') +
      javascript_tag("window.VAULT_I18N = #{i18n.to_json};")
  end
```

- [ ] **Step 2: Broaden the existing copy handler** so the detail card's copy works too.

In `assets/javascripts/vault.js`, change the selector on the copy handler from:
```js
  $(document).on("click", "#keys_table [data-clipboard-target]", function(e) {
```
to:
```js
  $(document).on("click", "#keys_table [data-clipboard-target], .vault-card [data-clipboard-target]", function(e) {
```

- [ ] **Step 3: Append the new JS** to the end of `assets/javascripts/vault.js`:
```js
// ---- Vault password linking: reveal, copy-link macro, editor toolbar + picker ----

// Reveal/hide a masked password on the detail card.
jQuery(document).on("click", ".vault-reveal", function(e) {
  e.preventDefault();
  var el = document.getElementById(jQuery(this).data("target"));
  if (!el) { return; }
  var hidden = (el.style.display === "none" || el.style.display === "");
  el.style.display = hidden ? "inline" : "none";
  jQuery(this).find("i.fa").toggleClass("fa-eye fa-eye-slash");
});

// Copy the {{pass(id)}} macro to the clipboard.
jQuery(document).on("click", ".vault-copy-link", function(e) {
  e.preventDefault();
  var id = jQuery(this).data("key-id");
  var icon = jQuery(this).find("i.fa").first();
  var prev = icon.attr("class");
  vaultCopyText("{{pass(" + id + ")}}").then(function() {
    if (prev) {
      icon.attr("class", "fa fa-check fa-fw");
      setTimeout(function() { icon.attr("class", prev); }, 1200);
    }
  });
});

function vaultI18n(k, fallback) {
  return (window.VAULT_I18N && window.VAULT_I18N[k]) || fallback;
}

// Current project identifier from the page context, or null.
function vaultCurrentProject() {
  var m = window.location.pathname.match(/\/projects\/([^\/?#]+)/);
  if (m) { return m[1]; }
  var a = document.querySelector("#main-menu a[href*='/projects/']");
  if (a) {
    var mm = a.getAttribute("href").match(/\/projects\/([^\/?#]+)/);
    if (mm) { return mm[1]; }
  }
  return null;
}

function vaultInsertAtCursor(textarea, text) {
  var start = textarea.selectionStart, end = textarea.selectionEnd, val = textarea.value;
  textarea.value = val.slice(0, start) + text + val.slice(end);
  var pos = start + text.length;
  textarea.selectionStart = textarea.selectionEnd = pos;
  textarea.focus();
}

function vaultClosePicker() {
  var ov = document.getElementById("vault-picker-overlay");
  if (ov) { ov.parentNode.removeChild(ov); }
}

function vaultRenderPickerList(listEl, items, textarea) {
  listEl.innerHTML = "";
  if (!items.length) {
    var empty = document.createElement("div");
    empty.className = "vault-picker-empty";
    empty.textContent = vaultI18n("picker_empty", "No passwords available");
    listEl.appendChild(empty);
    return;
  }
  items.forEach(function(it) {
    var row = document.createElement("a");
    row.href = "#";
    row.className = "vault-picker-item";
    row.innerHTML = "<i class='fa fa-lock fa-fw'></i> " +
      jQuery("<span>").text(it.name).html() + " <span class='vault-id'>#" + it.id + "</span>";
    row.addEventListener("click", function(e) {
      e.preventDefault();
      vaultInsertAtCursor(textarea, "{{pass(" + it.id + ")}}");
      vaultClosePicker();
    });
    listEl.appendChild(row);
  });
}

function vaultOpenPicker(textarea) {
  var proj = vaultCurrentProject();
  if (!proj) { vaultInsertAtCursor(textarea, "{{pass()}}"); return; }
  vaultClosePicker();

  var ov = document.createElement("div");
  ov.id = "vault-picker-overlay";
  ov.setAttribute("onclick", "if(event.target===this)vaultClosePicker();");

  var box = document.createElement("div");
  box.className = "vault-picker-box";
  box.innerHTML =
    "<div class='vault-picker-title'>" + vaultI18n("picker_title", "Insert password link") + "</div>" +
    "<input type='text' class='vault-picker-search' placeholder='" + vaultI18n("picker_search", "Search…") + "'>" +
    "<div class='vault-picker-list'></div>";
  ov.appendChild(box);
  document.body.appendChild(ov);

  var search = box.querySelector(".vault-picker-search");
  var listEl = box.querySelector(".vault-picker-list");
  var all = [];

  jQuery.getJSON("/projects/" + encodeURIComponent(proj) + "/keys/picker", function(items) {
    all = items || [];
    vaultRenderPickerList(listEl, all, textarea);
  });
  search.addEventListener("input", function() {
    var q = search.value.toLowerCase();
    vaultRenderPickerList(listEl, all.filter(function(it) {
      return it.name.toLowerCase().indexOf(q) !== -1 || String(it.id).indexOf(q) !== -1;
    }), textarea);
  });
  search.focus();
}

// Add a 🔒 button to every jsToolBar (textile editor).
function vaultAddToolbarButtons() {
  var bars = document.querySelectorAll(".jstElements");
  for (var i = 0; i < bars.length; i++) {
    var bar = bars[i];
    if (bar.querySelector(".vault-jst-pass")) { continue; }
    var textarea = bar.parentNode ? bar.parentNode.querySelector("textarea") : null;
    if (!textarea) { continue; }
    (function(ta, b) {
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "vault-jst-pass";
      btn.title = vaultI18n("insert_pass", "Insert password link");
      btn.innerHTML = "<i class='fa fa-lock'></i>";
      btn.addEventListener("click", function(e) { e.preventDefault(); vaultOpenPicker(ta); });
      b.appendChild(btn);
    })(textarea, bar);
  }
}

jQuery(function() {
  setTimeout(vaultAddToolbarButtons, 300); // after Redmine builds its toolbars
  jQuery(document).on("keydown", function(e) {
    if (e.key === "Escape" || e.keyCode === 27) { vaultClosePicker(); }
  });
});
```

- [ ] **Step 4: Syntax-check the JS**

Run: `node --check assets/javascripts/vault.js && echo OK`
Expected: `OK` (if node unavailable, skip; verified live after deploy).

- [ ] **Step 5: Commit**
```bash
git add init.rb assets/javascripts/vault.js
git commit -m "feat: editor toolbar pass-picker, reveal toggle, copy-link; VAULT_I18N"
```

---

## Task 6: List redesign + `#id` + copy-link action

**Files:**
- Modify: `app/views/keys/index.html.erb`
- Modify: `app/views/shared/_key_fields.html.erb`
- Modify: `app/views/shared/_key_actions.html.erb`

- [ ] **Step 1: Replace the heading+search block** in `index.html.erb` (lines 11–30, the `<h2>…</h2>` with the embedded form) with:
```erb
<h2><%= t('key.title.list') %></h2>

<div class="vault-toolbar">
  <%= form_tag({ controller: :keys, action: :index }, method: 'get', class: 'vault-search') do %>
    <%= text_field_tag(:query, @query, class: 'autocomplete') %>
    <span class="vault-search-scope">
      <label><%= radio_button_tag(:search_fild, "name", @search_fild == 'name') %> <%= t('key.attr.name') %></label>
      <label><%= radio_button_tag(:search_fild, "url",  @search_fild == 'url') %> <%= t('key.attr.url') %></label>
      <label><%= radio_button_tag(:search_fild, "tag",  @search_fild == 'tag') %> <%= t('key.attr.tags') %></label>
    </span>
    <%= submit_tag(t('button_update'), name: nil) %>
    <%= link_to t('button_clear'), { controller: :keys, action: :index, query: '' }, class: 'icon icon-reload vault-clear' %>
  <% end %>
</div>
```

- [ ] **Step 2: Show `#id`** in `app/views/shared/_key_fields.html.erb` — change the first `<td>` (name) to:
```erb
<td>
  <%= link_to key.name, edit_project_key_path(@project, key), class: 'keys-links' %>
  <span class="vault-id">#<%= key.id %></span>
</td>
```

- [ ] **Step 3: Add the copy-link action** at the END of `app/views/shared/_key_actions.html.erb`:
```erb
<a href="#" class="keys-actions vault-copy-link" data-key-id="<%= key.id %>" title="<%= t('key.btn.copy_link') %>">
  <i class='fa fa-link fa-fw'></i>
</a>
```

- [ ] **Step 4: Commit**
```bash
git add app/views/keys/index.html.erb app/views/shared/_key_fields.html.erb app/views/shared/_key_actions.html.erb
git commit -m "feat: clean Passwords list toolbar, visible #id, copy-link action"
```

---

## Task 7: Detail card

**Files:**
- Modify: `app/views/keys/show.html.erb`
- Create: `app/views/keys/_detail.html.erb`

- [ ] **Step 1: Rewrite `show.html.erb`**
```erb
<% content_for :header_tags do %>
  <%= stylesheet_link_tag "font-awesome.css", :plugin => "vault" %>
  <%= stylesheet_link_tag "font-awesome.min.css", :plugin => "vault" %>
  <%= javascript_include_tag 'vault', :plugin => 'vault' %>
<% end %>

<div class="contextual">
  <% if User.current.allowed_to?(:edit_keys, @project) %>
    <%= link_to t('key.title.edit'), edit_project_key_path(@project, @key), class: 'icon icon-edit' %>
    <%= link_to t('key.title.copy'), project_copy_key_path(@project, @key), class: 'icon icon-copy' %>
    <%= link_to t('key.title.delete'), project_key_path(@project, @key), method: :delete,
          data: { confirm: t('confirm.key.delete') }, class: 'icon icon-del' %>
  <% end %>
  <a href="#" class="icon icon-link vault-copy-link" data-key-id="<%= @key.id %>"><%= t('key.btn.copy_link') %></a>
</div>

<h2><%= @key.name %> <span class="vault-id">#<%= @key.id %></span></h2>

<%= render partial: 'keys/detail', locals: { key: @key } %>

<p><%= link_to t('button_back'), project_keys_path(@project) %></p>
```

- [ ] **Step 2: Create `app/views/keys/_detail.html.erb`**
```erb
<div class="box vault-card">
  <div class="attributes">
    <div class="attribute">
      <div class="label"><%= t('key.attr.login') %></div>
      <div class="value"><%= key.login.presence || '—' %></div>
    </div>
    <div class="attribute">
      <div class="label"><%= t('key.attr.url') %></div>
      <div class="value">
        <% if key.url.present? && key.url =~ /:\/\// %>
          <%= link_to key.url, key.url %>
        <% else %>
          <%= key.url.presence || '—' %>
        <% end %>
      </div>
    </div>
    <% unless key.is_a?(Vault::KeyFile) %>
      <div class="attribute">
        <div class="label"><%= t('key.attr.body') %></div>
        <div class="value vault-pass-value">
          <% if key.body.present? %>
            <label>*********</label>
            <label id="plain_pass_show_<%= key.id %>" style="display:none;"><%= key.body.to_s.force_encoding('UTF-8') %></label>
            <a href="#" class="keys-actions vault-reveal" data-target="plain_pass_show_<%= key.id %>" title="<%= t('key.btn.show') %>"><i class="fa fa-eye fa-fw"></i></a>
            <a href="#" class="keys-actions" data-clipboard-target="plain_pass_show_<%= key.id %>" title="<%= t('key.btn.clipboard') %>"><i class="fa fa-clipboard fa-fw"></i></a>
          <% else %>—<% end %>
        </div>
      </div>
    <% end %>
    <div class="attribute">
      <div class="label"><%= t('key.attr.tags') %></div>
      <div class="value vault-tags">
        <% key.tags.each do |tag| %><%= link_to "##{tag.name}", project_keys_path(key.project, query: "##{tag.name}"), class: 'vault-tag-chip' %><% end %>
      </div>
    </div>
  </div>

  <% if key.vault_attachments.any? %>
    <div class="vault-card-files">
      <h3><%= t('key.attr.attachments') %></h3>
      <ul>
        <% key.vault_attachments.order(:id).each do |att| %>
          <li>
            <%= link_to (att.filename.presence || "file ##{att.id}"), project_download_key_attachment_path(key.project, att), class: 'icon icon-file' %>
            <% if att.comment.present? %><span class="vault-att-comment">— <%= att.comment %></span><% end %>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <% if key.comment.present? %>
    <div class="vault-card-comment">
      <h3><%= t('key.attr.comment') %></h3>
      <%= textilizable key.comment %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Commit**
```bash
git add app/views/keys/show.html.erb app/views/keys/_detail.html.erb
git commit -m "feat: Redmine-native password detail card (reveal/copy, tags, files, comment)"
```

---

## Task 8: Edit-form attachments layout fix

**Files:**
- Modify: `app/views/keys/_form.html.erb`

- [ ] **Step 1: Wrap the attachments section heading as a tabular row.** In `_form.html.erb`, change the opening of the `.vault-attachments` block from:
```erb
    <div class="vault-attachments">
      <p><label><%= t('key.attr.attachments') %></label></p>
```
to:
```erb
    <div class="vault-attachments tabular">
      <p class="vault-attachments-head"><label class="vault-attachments-label"><%= t('key.attr.attachments') %></label></p>
```
(The matching CSS in Task 9 indents the rows under the input column and keeps the Delete control inside the box.)

- [ ] **Step 2: Commit**
```bash
git add app/views/keys/_form.html.erb
git commit -m "fix: structure attachments section for tabular alignment"
```

---

## Task 9: CSS

**Files:**
- Modify: `assets/stylesheets/vault.css`

- [ ] **Step 1: Append styles** to `assets/stylesheets/vault.css`:
```css
/* ---- list toolbar ---- */
.vault-toolbar { margin: 0 0 8px 0; }
.vault-toolbar .vault-search { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.vault-toolbar .vault-search-scope label { margin-right: 8px; font-weight: normal; white-space: nowrap; }
.vault-toolbar .vault-clear { margin-left: 4px; }
.vault-id { color: #999; font-size: 85%; font-weight: normal; }

/* ---- detail card ---- */
.vault-card .attributes { display: grid; grid-template-columns: max-content 1fr; gap: 4px 16px; }
.vault-card .attribute { display: contents; }
.vault-card .attribute .label { font-weight: bold; color: #555; padding-top: 2px; }
.vault-card .attribute .value { word-break: break-word; }
.vault-card .vault-pass-value label { font-family: monospace; }
.vault-tag-chip { display: inline-block; background: #eef; border: 1px solid #ccd; border-radius: 10px;
  padding: 0 8px; margin: 0 4px 4px 0; font-size: 85%; text-decoration: none; }
.vault-card-files, .vault-card-comment { margin-top: 12px; }
.vault-card-files ul { list-style: none; margin: 4px 0; padding: 0; }
.vault-card-files li { margin: 2px 0; }
.vault-att-comment { color: #777; }
.vault-pass-noaccess, .vault-pass-notfound { color: #999; }

/* ---- edit-form attachments: align under input column, keep Delete inside the box ---- */
.edit_vault_key .vault-attachments { clear: left; padding-left: 180px; margin: 6px 0; }
.edit_vault_key .vault-attachments .vault-attachments-label { float: left; margin-left: -180px; width: 175px;
  font-weight: bold; padding-top: .45em; }
.vault-attachment-row, .vault-new-attachment { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; margin: 3px 0; }
.vault-attachment-del { white-space: nowrap; margin-left: 4px; }
#vault-add-attachment { display: inline-block; margin-top: 4px; }

/* ---- editor toolbar button ---- */
button.vault-jst-pass { background: transparent; border: none; cursor: pointer; padding: 2px 5px; color: #555; }
button.vault-jst-pass:hover { color: #c61a1a; }

/* ---- picker modal ---- */
#vault-picker-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%;
  background: rgba(0,0,0,0.5); z-index: 10000; display: flex; justify-content: center; align-items: flex-start; }
.vault-picker-box { background: #fff; border-radius: 8px; margin-top: 10vh; padding: 14px; width: 420px;
  max-width: 90vw; box-shadow: 0 8px 30px rgba(0,0,0,0.4); }
.vault-picker-title { font-weight: bold; margin-bottom: 8px; }
.vault-picker-search { width: 100%; box-sizing: border-box; padding: .3em .4em; margin-bottom: 8px; }
.vault-picker-list { max-height: 50vh; overflow-y: auto; }
.vault-picker-item { display: block; padding: 5px 6px; text-decoration: none; color: #333; border-radius: 4px; }
.vault-picker-item:hover { background: #eef; }
.vault-picker-empty { color: #999; padding: 8px; }
```

- [ ] **Step 2: Commit**
```bash
git add assets/stylesheets/vault.css
git commit -m "style: list toolbar, detail card, tag chips, picker modal, attachments-fix"
```

---

## Task 10: Version bump + deploy + live verification (all 3 hosts)

**Files:**
- Modify: `init.rb`

- [ ] **Step 1: Bump version** in `init.rb`: `version '0.6.1'` → `version '0.7.0'`. Commit:
```bash
git add init.rb && git commit -m "chore: bump version to 0.7.0"
```

- [ ] **Step 2: Push**
```bash
git push origin redmine-6.1
```

- [ ] **Step 3: Confirm text formatting on all 3 hosts** (toolbar targets textile)

Per host (`sudo ssh -p 5022`, pw from Vaultwarden item `Mac sudo — sergiikarlovskyi` 68dbb61b…), run:
`cd <root> && sudo -u <owner> RAILS_ENV=production bin/rails runner "puts Setting.text_formatting"`
Expected: `textile` on each. If any returns `markdown`/`common_mark`, add that editor's insert path before relying on the button there (note it; the macro + copy-link still work regardless).

- [ ] **Step 4: Deploy per host** (red.half canary → vs-com → volia). JS **and** CSS changed → precompile required.
```
git -C plugins/vault fetch origin redmine-6.1 && git -C plugins/vault reset --hard origin/redmine-6.1
sudo -u <owner> RAILS_ENV=production bin/rails assets:precompile
sudo -u <owner> touch tmp/restart.txt   # ensure restart.txt is app-owned first (root-owned silently blocks restart)
```
Confirm restart: `ps -eo lstart,args | grep 'Passenger RubyApp'` shows a fresh start time.
Owners: red.half=`www-data` (/var/www/redmine), vs-com=`web1` (/var/www/clients/client1/web1/web), volia=`www-data` (/var/www/redmine).

- [ ] **Step 5: Live-verify on red.half**
  - List: search toolbar on one line under the title; `#id` shows; `⧉ link` icon present; clicking it copies `{{pass(<id>)}}`.
  - Detail (`/projects/office/keys/<id>`): card layout; `👁` reveals password; `⧉` copies it; tags as chips; files + comments; `⧉ link` in contextual.
  - Macro: paste `{{pass(<id>)}}` into an issue description → renders `🔒 <name>` link; a user without access sees `🔒 (no access)`.
  - Toolbar: in an issue editor, the 🔒 button opens the picker listing the project's accessible passwords; selecting inserts `{{pass(<id>)}}`.
  - Edit form: attachments section aligned under the input column; Delete control inside the box.

- [ ] **Step 6: Repeat live-verify on vs-com + volia (smoke).** Commit nothing further; deployment is git-reset based.

---

## Self-review notes

- Spec coverage: Plane A→Task 6; Plane B→Task 7; Plane C→Tasks 2–3; Plane D→Tasks 4–5; Plane E→Tasks 8–9; Plane F→Tasks 5–7; i18n→Task 1; deploy→Task 10. Phase 2 (GCM) and Vaultwarden are intentionally out of this plan.
- The copy handler selector is broadened (Task 5 Step 2) so the detail card's `data-clipboard-target` works outside `#keys_table`.
- `vault-copy-link`, `vault-reveal`, `vault-jst-pass`, `vault-picker-*`, `vault-id`, `vault-tag-chip` class names are consistent across JS (Task 5), views (Tasks 6–7), and CSS (Task 9).
