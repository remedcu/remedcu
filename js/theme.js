/* Theme toggle. Dark is the default; "light" is stored when chosen.
   Loaded synchronously in <head>: it applies a stored choice and sets
   html[data-js] before first paint, so the CSS can show the toggle at once
   (no layout shift). DARK and LIGHT must equal --bg in css/site.css. */
(function () {
  var KEY = "theme", DARK = "#121315", LIGHT = "#fcfcfb";
  var root = document.documentElement;
  var btn = null;

  function stored() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }

  function isLight() { return root.getAttribute("data-theme") === "light"; }

  function apply(light) {
    if (light) { root.setAttribute("data-theme", "light"); } else { root.removeAttribute("data-theme"); }
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) { meta.setAttribute("content", light ? LIGHT : DARK); }
    if (btn) {
      btn.textContent = light ? "Dark" : "Light";
      btn.setAttribute("aria-label", light ? "Switch to dark theme" : "Switch to light theme");
    }
  }

  root.setAttribute("data-js", "");
  apply(stored() === "light");

  document.addEventListener("DOMContentLoaded", function () {
    btn = document.querySelector(".theme-toggle");
    if (!btn) { return; }
    btn.hidden = false;
    apply(isLight());
    btn.addEventListener("click", function () {
      var light = !isLight();
      try { localStorage.setItem(KEY, light ? "light" : "dark"); } catch (e) { /* storage unavailable */ }
      apply(light);
    });
  });

  /* Follow a choice made in another tab, or on another page before Back restored this one. */
  window.addEventListener("storage", function (e) {
    if (e.key === KEY) { apply(e.newValue === "light"); }
  });
  window.addEventListener("pageshow", function (e) {
    var s = stored();
    if (e.persisted && s) { apply(s === "light"); }
  });
})();
