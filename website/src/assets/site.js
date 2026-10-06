// Theme toggle (light/dark, remembered per browser) and copy buttons on code
// blocks. The site works without it; the theme then follows the system.
(function () {
  var root = document.documentElement;
  function current() {
    var set = root.getAttribute('data-theme');
    if (set) return set;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  var toggle = document.querySelector('.theme-toggle');
  if (toggle) {
    toggle.addEventListener('click', function () {
      var next = current() === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('nab-theme', next); } catch (e) { /* private mode */ }
    });
  }

  document.querySelectorAll('.prose pre, .code-window pre').forEach(function (pre) {
    if (!navigator.clipboard) return;
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy';
    button.textContent = 'Copy';
    button.addEventListener('click', function () {
      var code = pre.querySelector('code') || pre;
      navigator.clipboard.writeText(code.innerText).then(function () {
        button.textContent = 'Copied';
        setTimeout(function () { button.textContent = 'Copy'; }, 1500);
      });
    });
    pre.appendChild(button);
  });

  // Close the mobile menu after choosing a link.
  var navToggle = document.getElementById('nav-toggle');
  document.querySelectorAll('.nav-wrap a').forEach(function (a) {
    a.addEventListener('click', function () { if (navToggle) navToggle.checked = false; });
  });
})();
