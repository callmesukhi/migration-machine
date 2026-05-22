// migration-machine site - small progressive enhancements (no dependencies)

(function () {
  "use strict";

  // Copy-to-clipboard. A button copies its data-copy text, or falls back to
  // the nearest code block / terminal body.
  function textFor(btn) {
    var t = btn.getAttribute("data-copy");
    if (t) return t;
    var wrap = btn.closest(".codewrap, .term");
    var el = wrap && wrap.querySelector("pre, .term-body");
    return el ? el.innerText : "";
  }

  function copy(text) {
    text = (text || "").trim();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy"); } catch (e) {}
      document.body.removeChild(ta);
      resolve();
    });
  }

  document.querySelectorAll(".copy").forEach(function (btn) {
    btn.addEventListener("click", function () {
      copy(textFor(btn)).then(function () {
        var prev = btn.textContent;
        btn.textContent = "copied";
        btn.classList.add("done");
        setTimeout(function () {
          btn.textContent = prev;
          btn.classList.remove("done");
        }, 1400);
      });
    });
  });

  // Mobile nav toggle
  var toggle = document.querySelector(".nav-toggle");
  var links = document.querySelector(".nav-links");
  if (toggle && links) {
    toggle.addEventListener("click", function () {
      links.classList.toggle("open");
    });
  }

  // Active nav link based on <body data-page="...">
  var page = document.body.getAttribute("data-page");
  if (page) {
    document.querySelectorAll(".nav-links a[data-page]").forEach(function (a) {
      if (a.getAttribute("data-page") === page) a.classList.add("active");
    });
  }
})();
