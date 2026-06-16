// Vault preview modal
function vaultCloseModal() {
  var ov = document.getElementById("vault-modal-overlay");
  if (ov) { ov.style.display = "none"; }
  var img = document.getElementById("vault-modal-img");
  if (img) { img.src = ""; }
  var ifr = document.getElementById("vault-modal-iframe");
  if (ifr) { ifr.src = ""; ifr.style.display = "none"; }
}

function vaultOpenModal(url) {
  var img = document.getElementById("vault-modal-img");
  var ifr = document.getElementById("vault-modal-iframe");
  img.style.display = "block";
  img.src = url;
  ifr.style.display = "none";
  ifr.src = "";
  img.onerror = function() {
    img.style.display = "none";
    ifr.style.display = "block";
    ifr.src = url;
  };
  document.getElementById("vault-modal-overlay").style.display = "flex";
}

// Copy text to the clipboard, with a fallback for non-secure contexts (http).
function vaultCopyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text);
  }
  var ta = document.createElement("textarea");
  ta.value = text;
  ta.style.cssText = "position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;";
  document.body.appendChild(ta);
  ta.focus();
  ta.select();
  try { document.execCommand("copy"); } catch (e) {}
  document.body.removeChild(ta);
  return Promise.resolve();
}

$(document).ready(function() {
  if (!document.getElementById("vault-modal-overlay")) {
    // Overlay - covers full screen, flex center
    var ov = document.createElement("div");
    ov.id = "vault-modal-overlay";
    ov.setAttribute("onclick", "if(event.target===this)vaultCloseModal();");
    ov.style.cssText = "display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.75);z-index:10000;justify-content:center;align-items:center;";

    // Modal box - white background, rounded, relative for close btn
    var box = document.createElement("div");
    box.style.cssText = "position:relative;background:#fff;border-radius:8px;padding:20px;max-width:85vw;max-height:85vh;box-shadow:0 8px 30px rgba(0,0,0,0.6);";

    // Close button - top right corner of the box
    var closeBtn = document.createElement("div");
    closeBtn.setAttribute("onclick", "vaultCloseModal();");
    closeBtn.style.cssText = "position:absolute;top:-12px;right:-12px;width:30px;height:30px;line-height:30px;text-align:center;font-size:18px;font-weight:bold;color:#fff;background:#e74c3c;border-radius:50%;cursor:pointer;z-index:10001;box-shadow:0 2px 6px rgba(0,0,0,0.3);";
    closeBtn.innerHTML = "&#x2715;";

    // Image
    var img = document.createElement("img");
    img.id = "vault-modal-img";
    img.style.cssText = "display:block;max-width:70vw;max-height:75vh;border-radius:4px;";

    // Iframe fallback
    var ifr = document.createElement("iframe");
    ifr.id = "vault-modal-iframe";
    ifr.style.cssText = "display:none;width:70vw;height:70vh;border:none;border-radius:4px;";

    box.appendChild(closeBtn);
    box.appendChild(img);
    box.appendChild(ifr);
    ov.appendChild(box);
    document.body.appendChild(ov);
  }

  $(document).on("click", ".vault-preview-link", function(e) {
    e.preventDefault();
    vaultOpenModal($(this).attr("href"));
  });

  $(document).on("keydown", function(e) {
    if (e.key === "Escape" || e.keyCode === 27) vaultCloseModal();
  });

  // Copy a key field (password / login / url) to the clipboard.
  // Each trigger's data-clipboard-target is the id of the element holding the value,
  // so the Password icon copies the password, the URL icon the URL, etc.
  // Self-contained on purpose: Redmine 6.x core only wires data-clipboard-text (a literal),
  // not data-clipboard-target, so without this the icons copy the wrong field (or nothing).
  $(document).on("click", "#keys_table [data-clipboard-target], .vault-card [data-clipboard-target]", function(e) {
    e.preventDefault();
    e.stopPropagation();
    var el = document.getElementById($(this).attr("data-clipboard-target"));
    if (!el) { return; }
    var text = (typeof el.value === "string" && el.value !== "") ? el.value : el.textContent;
    var icon = $(this).find("i.fa").first();
    var prev = icon.attr("class");
    vaultCopyText(text).then(function() {
      if (prev) {
        icon.attr("class", "fa fa-check fa-fw");
        setTimeout(function() { icon.attr("class", prev); }, 1200);
      }
    });
  });
});

// "+ add file" on the key form: clone an empty file+comment row.
jQuery(document).on("click", "#vault-add-attachment", function(e) {
  e.preventDefault();
  var container = document.getElementById("vault-new-attachments");
  var first = container && container.querySelector(".vault-new-attachment");
  if (!first) { return; }
  var clone = first.cloneNode(true);
  jQuery(clone).find("input").val("");
  container.appendChild(clone);
});

// ---- Vault password linking: reveal, copy-link macro, editor toolbar + picker ----

// Reveal/hide a masked password on the detail card.
jQuery(document).on("click", ".vault-reveal", function(e) {
  e.preventDefault();
  var el = document.getElementById(jQuery(this).data("target"));
  if (!el) { return; }
  var show = (el.style.display === "none" || el.style.display === "");
  el.style.display = show ? "inline" : "none";
  jQuery(el).siblings(".vault-mask").css("display", show ? "none" : "inline");
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
