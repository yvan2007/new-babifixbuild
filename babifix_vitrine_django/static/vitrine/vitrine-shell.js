(function () {
  'use strict';

  var STORAGE_KEY = 'babifix_vitrine_theme';
  var VALID_THEMES = ['blanc', 'clair', 'sombre'];

  function applyTheme(theme) {
    var safe = VALID_THEMES.indexOf(theme) !== -1 ? theme : 'blanc';
    document.documentElement.setAttribute('data-theme', safe);
    try {
      localStorage.setItem(STORAGE_KEY, safe);
    } catch (e) {
      /* stockage indisponible */
    }
    document.querySelectorAll('.bx-theme-btn[data-set-theme]').forEach(function (btn) {
      var active = btn.getAttribute('data-set-theme') === safe;
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
  }

  /* Synchroniser l'etat des boutons au chargement du DOM */
  var current = document.documentElement.getAttribute('data-theme') || 'blanc';
  applyTheme(current);

  document.querySelectorAll('.bx-theme-btn[data-set-theme]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      applyTheme(btn.getAttribute('data-set-theme'));
    });
  });

  /* Barre de progression + navbar sticky */
  var bar = document.getElementById('progress-bar');
  var nav = document.getElementById('bxTopNav');
  var navLinks = Array.from(document.querySelectorAll('.bx-nav-links a[data-section]'));
  var trackedSections = navLinks
    .map(function (a) { return document.getElementById(a.getAttribute('data-section')); })
    .filter(Boolean);

  function onScroll() {
    var st = window.scrollY || 0;
    var sh = document.documentElement.scrollHeight - window.innerHeight;
    if (bar) {
      bar.style.width = (sh > 0 ? Math.min(100, (st / sh) * 100) : 0) + '%';
    }
    if (nav) {
      nav.classList.toggle('scrolled', st > 24);
    }
    if (trackedSections.length) {
      var scrollMid = st + window.innerHeight * 0.35;
      var activeSec = trackedSections.reduce(function (acc, sec) {
        return sec.offsetTop <= scrollMid ? sec : acc;
      }, trackedSections[0]);
      if (activeSec) {
        navLinks.forEach(function (a) {
          a.classList.toggle('active', a.getAttribute('data-section') === activeSec.id);
        });
      }
    }
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  /* Tiroir navigation mobile */
  var burger = document.getElementById('bxBurgerBtn');
  var overlay = document.getElementById('bxNavOverlay');
  var drawer = document.getElementById('bxNavDrawer');
  var drawerClose = document.getElementById('bxDrawerClose');

  function openDrawer() {
    if (!drawer) return;
    if (burger) {
      burger.classList.add('open');
      burger.setAttribute('aria-expanded', 'true');
    }
    if (overlay) {
      overlay.classList.add('open');
      overlay.setAttribute('aria-hidden', 'false');
    }
    drawer.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function closeDrawer() {
    if (!drawer) return;
    if (burger) {
      burger.classList.remove('open');
      burger.setAttribute('aria-expanded', 'false');
    }
    if (overlay) {
      overlay.classList.remove('open');
      overlay.setAttribute('aria-hidden', 'true');
    }
    drawer.classList.remove('open');
    document.body.style.overflow = '';
  }

  if (burger) burger.addEventListener('click', openDrawer);
  if (overlay) overlay.addEventListener('click', closeDrawer);
  if (drawerClose) drawerClose.addEventListener('click', closeDrawer);
  if (drawer) {
    drawer.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', closeDrawer);
    });
  }

  /* Ouverture rapide des preferences cookies depuis le footer ou la page Cookies */
  document.querySelectorAll('[data-open-cookie-prefs]').forEach(function (trigger) {
    trigger.addEventListener('click', function () {
      var openBtn = document.getElementById('cookieCustomize') || document.getElementById('cookie-customize');
      var modal = document.getElementById('cookieModal') || document.getElementById('cookie-modal');
      var banner = document.getElementById('cookieBanner') || document.getElementById('cookie-banner');
      if (openBtn) {
        openBtn.click();
      } else if (modal) {
        modal.classList.add('open');
        modal.style.display = 'flex';
      } else if (banner) {
        banner.classList.add('visible');
      }
    });
  });
})();
