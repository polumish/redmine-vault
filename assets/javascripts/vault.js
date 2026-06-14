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
  $(document).on("click", "#keys_table [data-clipboard-target]", function(e) {
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
