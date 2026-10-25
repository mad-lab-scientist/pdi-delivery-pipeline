/* Pearson Cyber Defense: site behavior.
   No dependencies. CSP-safe: no inline handlers, no eval, no third-party calls.
   Talks to the existing mrpearson.net API: /api/csrf-token, /api/contact, /api/checkout, /api/analytics/event. */
(function () {
  'use strict';
  var doc = document;
  var root = doc.documentElement;
  root.classList.add('js');
  var reduceMotion = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  var CONTACT_FALLBACK = 'Email admin@mrpearson.net or call (256) 675-9961.';

  function onMedia(query, fn) {
    if (!window.matchMedia) return;
    var mq = window.matchMedia(query);
    if (mq.addEventListener) mq.addEventListener('change', fn); else if (mq.addListener) mq.addListener(fn);
  }

  // ------------------------------------------------------------ header + mobile nav
  var header = doc.querySelector('[data-header]');
  function onScroll() { if (header) header.classList.toggle('is-scrolled', window.scrollY > 8); }
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  var toggle = doc.querySelector('[data-nav-toggle]');
  var nav = doc.querySelector('[data-nav]');
  function setNav(open) {
    if (!toggle || !nav) return;
    toggle.setAttribute('aria-expanded', String(open));
    nav.classList.toggle('is-open', open);
    doc.body.classList.toggle('nav-open', open);
  }
  if (toggle && nav) {
    toggle.addEventListener('click', function () { setNav(toggle.getAttribute('aria-expanded') !== 'true'); });
    doc.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') { setNav(false); toggle.focus(); }
    });
    nav.addEventListener('click', function (ev) { if (ev.target.closest && ev.target.closest('a')) setNav(false); });
    onMedia('(min-width: 1061px)', function (m) { if (m.matches) setNav(false); });
  }

  // ------------------------------------------------------------ reveal on scroll (below the fold only: no flicker)
  if (!reduceMotion && 'IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        en.target.classList.remove('reveal-pending');
        en.target.classList.add('revealed');
        io.unobserve(en.target);
      });
    }, { rootMargin: '0px 0px -6% 0px', threshold: 0.06 });
    var fold = window.innerHeight;
    doc.querySelectorAll('.section-head, .card, .step, .sla-tile, .stack, .timeline-item, .outcomes li, .fact-grid li').forEach(function (el) {
      if (el.getBoundingClientRect().top > fold) { el.classList.add('reveal-pending'); io.observe(el); }
    });
  }

  // ------------------------------------------------------------ stack explorer
  doc.querySelectorAll('[data-stack]').forEach(function (stack) {
    var buttons = Array.prototype.slice.call(stack.querySelectorAll('[data-layer]'));
    function activate(btn) {
      buttons.forEach(function (b) {
        var on = b === btn;
        b.classList.toggle('is-active', on);
        b.setAttribute('aria-expanded', String(on));
        var panel = doc.getElementById(b.getAttribute('aria-controls'));
        if (panel) panel.classList.toggle('is-active', on);
      });
    }
    var canHover = !!(window.matchMedia && window.matchMedia('(hover: hover)').matches);
    buttons.forEach(function (b, i) {
      b.addEventListener('click', function () { activate(b); });
      b.addEventListener('focus', function () { activate(b); });
      if (canHover) b.addEventListener('mouseenter', function () { activate(b); });
      b.addEventListener('keydown', function (ev) {
        var next = null;
        if (ev.key === 'ArrowDown') next = buttons[(i + 1) % buttons.length];
        if (ev.key === 'ArrowUp') next = buttons[(i - 1 + buttons.length) % buttons.length];
        if (next) { ev.preventDefault(); next.focus(); }
      });
    });
  });

  // ------------------------------------------------------------ terminal typing (content is already in the HTML)
  doc.querySelectorAll('[data-terminal]').forEach(function (term) {
    if (reduceMotion) return;
    var items = Array.prototype.slice.call(term.querySelectorAll('.terminal-body li')).filter(function (li) { return !li.classList.contains('t-cursor'); });
    if (!items.length) return;
    var texts = items.map(function (li) { return li.textContent; });
    items.forEach(function (li) { li.textContent = ''; });
    var i = 0;
    function typeLine() {
      if (i >= items.length) return;
      var li = items[i];
      var full = texts[i];
      var isCmd = li.classList.contains('t-cmd');
      var n = 0;
      var stepChars = isCmd ? 2 : 6;
      (function tick() {
        n = Math.min(full.length, n + stepChars);
        li.textContent = full.slice(0, n);
        if (n < full.length) { setTimeout(tick, isCmd ? 30 : 12); return; }
        i += 1;
        setTimeout(typeLine, isCmd ? 420 : 170);
      })();
    }
    var started = false;
    function start() { if (!started) { started = true; setTimeout(typeLine, 400); } }
    if ('IntersectionObserver' in window) {
      var obs = new IntersectionObserver(function (en) { if (en[0].isIntersecting) { start(); obs.disconnect(); } });
      obs.observe(term);
    } else { start(); }
  });

  // ------------------------------------------------------------ CMMC Phase 2 countdown
  doc.querySelectorAll('[data-countdown]').forEach(function (el) {
    var target = Date.parse(el.getAttribute('data-countdown'));
    var daysEl = el.querySelector('[data-countdown-days]');
    var unitEl = el.querySelector('[data-countdown-unit]');
    var label = el.querySelector('.countdown-label');
    if (isNaN(target) || !daysEl) return;
    var ms = target - Date.now();
    if (ms > 0) {
      var d = Math.ceil(ms / 86400000);
      daysEl.textContent = String(d);
      if (unitEl) unitEl.textContent = d === 1 ? 'day to go' : 'days to go';
    } else {
      var since = Math.floor(-ms / 86400000);
      daysEl.textContent = String(since);
      if (unitEl) unitEl.textContent = since === 1 ? 'day in effect' : 'days in effect';
      if (label) label.textContent = 'CMMC Phase 2 in effect since November 10, 2026';
    }
  });

  // ------------------------------------------------------------ 404 path echo
  var p404 = doc.querySelector('[data-404-path]');
  if (p404) p404.textContent = '$ curl -I https://mrpearson.net' + window.location.pathname.slice(0, 80);

  // ------------------------------------------------------------ API helpers (CSRF compatible with the existing backend)
  function csrfMeta() { return doc.querySelector('meta[name="csrf-token"]'); }
  function getToken() {
    var m = csrfMeta();
    var t = m ? m.getAttribute('content') : '';
    if (t) return Promise.resolve(t);
    return fetch('/api/csrf-token', { headers: { Accept: 'application/json' }, credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : {}; })
      .then(function (j) { var tok = (j && j.csrfToken) || ''; if (m && tok) m.setAttribute('content', tok); return tok; })
      .catch(function () { return ''; });
  }
  function refreshToken() { var m = csrfMeta(); if (m) m.setAttribute('content', ''); return getToken(); }
  function postJson(url, data, tokenInBody) {
    function send(tok) {
      var body = {};
      Object.keys(data).forEach(function (k) { body[k] = data[k]; });
      if (tokenInBody && tok) body._csrf = tok;
      return fetch(url, {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'x-csrf-token': tok || '' },
        body: JSON.stringify(body),
      }).then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (j) { j = j || {}; j.status = r.status; return j; });
      });
    }
    return getToken().then(send).then(function (res) {
      if (res.status === 403 && /csrf/i.test(res.message || '')) return refreshToken().then(send);
      return res;
    });
  }
  function track(type, label) {
    if (!window.fetch) return;
    getToken().then(function (tok) {
      fetch('/api/analytics/event', {
        method: 'POST', credentials: 'same-origin', keepalive: true,
        headers: { 'Content-Type': 'application/json', 'x-csrf-token': tok || '' },
        body: JSON.stringify({ eventType: type, label: String(label || '').slice(0, 80), path: window.location.pathname }),
      }).catch(function () {});
    });
  }
  doc.querySelectorAll('[data-track-event]').forEach(function (el) {
    el.addEventListener('click', function () { track(el.getAttribute('data-track-event'), el.getAttribute('data-track-label') || ''); });
  });

  // ------------------------------------------------------------ forms
  function field(form, name) { return form.querySelector('[name="' + name + '"]'); }
  function val(form, name) { var f = field(form, name); return f ? String(f.value || '').trim() : ''; }
  function setStatus(el, cls, msg) { if (!el) return; el.className = 'form-status' + (cls ? ' ' + cls : ''); el.textContent = msg; }
  function setBusy(btn, busy, text) {
    if (!btn) return;
    if (busy) { btn.setAttribute('data-label', btn.innerHTML); btn.disabled = true; btn.textContent = text; }
    else { btn.disabled = false; if (btn.getAttribute('data-label')) btn.innerHTML = btn.getAttribute('data-label'); }
  }
  function validate(form) {
    var first = null;
    form.querySelectorAll('input, select, textarea').forEach(function (f) {
      var bad = (f.required && !String(f.value || '').trim()) || (f.type === 'email' && f.value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.value)) || (f.type === 'number' && f.value && f.min && parseFloat(f.value) < parseFloat(f.min));
      if (bad) { f.setAttribute('aria-invalid', 'true'); if (!first) first = f; } else { f.removeAttribute('aria-invalid'); }
    });
    if (first) { first.focus(); setStatus(form.querySelector('.form-status'), 'is-error', 'Please check the highlighted field.'); return false; }
    return true;
  }
  function doneNode(title, text) {
    var wrap = doc.createElement('div');
    wrap.className = 'form-done';
    var a = doc.createElement('p'); a.className = 'mono'; a.textContent = title;
    var b = doc.createElement('p'); b.textContent = text;
    wrap.appendChild(a); wrap.appendChild(b);
    return wrap;
  }

  doc.querySelectorAll('[data-contact-form]').forEach(function (form) {
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      if (!validate(form)) return;
      var status = form.querySelector('.form-status');
      var btn = form.querySelector('button[type="submit"]');
      var data = {
        name: val(form, 'name'), email: val(form, 'email'), company: val(form, 'company'),
        service: val(form, 'service'), message: val(form, 'message'),
        sourcePage: form.getAttribute('data-source-page') || 'contact',
      };
      setBusy(btn, true, 'Sending…');
      setStatus(status, '', '');
      postJson('/api/contact', data, false).then(function (res) {
        if (res && res.success) {
          track('contact_submit', data.service || data.sourcePage);
          form.replaceChildren(doneNode('✓ request received', 'Thanks. We reply within 1 business day.'));
          return;
        }
        setStatus(status, 'is-error', (res && res.message) || ('That didn’t go through. ' + CONTACT_FALLBACK));
        setBusy(btn, false);
      }).catch(function () {
        setStatus(status, 'is-error', 'Network error. ' + CONTACT_FALLBACK);
        setBusy(btn, false);
      });
    });
  });

  doc.querySelectorAll('[data-invoice-form]').forEach(function (form) {
    // Stripe Checkout sends a canceled payer back to /payments?canceled=1.
    if (/[?&]canceled=1(?:&|$)/.test(window.location.search)) setStatus(form.querySelector('.form-status'), '', 'Checkout was canceled. No payment was processed.');
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      if (!validate(form)) return;
      var status = form.querySelector('.form-status');
      var btn = form.querySelector('button[type="submit"]');
      var data = { planKey: 'custom-invoice', invoiceNumber: val(form, 'invoiceNumber'), amount: val(form, 'amount'), email: val(form, 'email') };
      setBusy(btn, true, 'Opening secure checkout…');
      setStatus(status, '', '');
      postJson('/api/checkout', data, true).then(function (res) {
        // Only ever redirect to Stripe-hosted checkout.
        if (res && res.success && typeof res.url === 'string' && /^https:\/\/checkout\.stripe\.com\//.test(res.url)) {
          track('checkout_redirect', 'custom-invoice');
          setStatus(status, 'is-ok', 'Redirecting to Stripe…');
          window.location.assign(res.url);
          return;
        }
        setStatus(status, 'is-error', (res && res.message) || 'Checkout couldn’t start. Email admin@mrpearson.net.');
        setBusy(btn, false);
      }).catch(function () {
        setStatus(status, 'is-error', 'Checkout is unavailable right now. Email admin@mrpearson.net.');
        setBusy(btn, false);
      });
    });
  });
})();
