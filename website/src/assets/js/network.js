/* Hero "defended network" animation.
   Nodes and links form a live topology; data packets flow along links; occasional threat packets
   are intercepted at shield nodes (amber flash, then green). Decorative only (aria-hidden canvas).
   Pauses off-screen and in background tabs; draws a single static frame for reduced motion. */
(function () {
  'use strict';
  var canvas = document.querySelector('[data-network]');
  if (!canvas || !canvas.getContext) return;
  var ctx = canvas.getContext('2d');
  if (!ctx) return;
  var reduce = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  var CYAN = '34,211,238';
  var GREEN = '74,222,128';
  var RED = '248,113,113';
  var AMBER = '251,191,36';
  var W = 0, H = 0, dpr = 1, nodes = [], links = [], adj = [], packets = [];
  var raf = 0, last = 0, spawnAcc = 0, onScreen = true, t0 = performance.now();

  function rand(a, b) { return a + Math.random() * (b - a); }

  function build() {
    var rect = canvas.getBoundingClientRect();
    W = Math.max(1, rect.width);
    H = Math.max(1, rect.height);
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    var wide = W >= 960;
    var count = Math.round(Math.min(70, Math.max(24, (W * H) / 24000)));
    nodes = [];
    for (var i = 0; i < count; i++) {
      var x = wide ? W * (0.3 + 0.7 * Math.pow(Math.random(), 0.85)) : W * Math.random();
      var y = H * rand(0.06, 0.94);
      nodes.push({ ox: x, oy: y, x: x, y: y, ax: rand(4, 14), ay: rand(4, 14), fx: rand(0.00012, 0.00032), fy: rand(0.00012, 0.00032), ph: rand(0, Math.PI * 2), r: rand(1.1, 2.2), shield: false, pulse: 0 });
    }
    var shields = Math.max(3, Math.round(count / 11));
    for (var s = 0; s < shields; s++) { var n = nodes[(s * 7919) % nodes.length]; n.shield = true; n.r = 3.2; }

    links = [];
    adj = nodes.map(function () { return []; });
    var maxD = Math.max(120, Math.min(200, W / 7));
    var seen = {};
    for (var a = 0; a < nodes.length; a++) {
      var near = [];
      for (var b = 0; b < nodes.length; b++) {
        if (a === b) continue;
        var dx = nodes[a].ox - nodes[b].ox, dy = nodes[a].oy - nodes[b].oy;
        var d = Math.sqrt(dx * dx + dy * dy);
        if (d < maxD) near.push([d, b]);
      }
      near.sort(function (p, q) { return p[0] - q[0]; });
      for (var k = 0; k < Math.min(3, near.length); k++) {
        var lo = Math.min(a, near[k][1]), hi = Math.max(a, near[k][1]), key = lo + ':' + hi;
        if (seen[key]) continue;
        seen[key] = true;
        var idx = links.push({ a: lo, b: hi }) - 1;
        adj[lo].push(idx); adj[hi].push(idx);
      }
    }
    packets = [];
  }

  function spawn() {
    if (!links.length || packets.length > 28) return;
    var threat = Math.random() < 0.1;
    var li, from, to;
    if (threat) {
      var shieldIdx = [];
      nodes.forEach(function (n, i) { if (n.shield && adj[i].length) shieldIdx.push(i); });
      if (!shieldIdx.length) return;
      to = shieldIdx[Math.floor(Math.random() * shieldIdx.length)];
      li = adj[to][Math.floor(Math.random() * adj[to].length)];
      from = links[li].a === to ? links[li].b : links[li].a;
    } else {
      li = Math.floor(Math.random() * links.length);
      var flip = Math.random() < 0.5;
      from = flip ? links[li].a : links[li].b;
      to = flip ? links[li].b : links[li].a;
    }
    packets.push({ from: from, to: to, t: 0, speed: rand(0.00032, 0.0006) * (threat ? 0.8 : 1), threat: threat, hops: 0, color: threat ? RED : (Math.random() < 0.55 ? CYAN : GREEN) });
  }

  function step(dt, now) {
    var tt = now - t0;
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      n.x = n.ox + Math.sin(tt * n.fx + n.ph) * n.ax;
      n.y = n.oy + Math.cos(tt * n.fy + n.ph) * n.ay;
      if (n.pulse > 0) n.pulse = Math.max(0, n.pulse - dt * 0.0011);
    }
    spawnAcc += dt;
    while (spawnAcc > 180) { spawnAcc -= 180; spawn(); }
    for (var p = packets.length - 1; p >= 0; p--) {
      var k = packets[p];
      k.t += k.speed * dt;
      if (k.t < 1) continue;
      var dest = nodes[k.to];
      if (k.threat) { dest.pulse = 1; packets.splice(p, 1); continue; }
      if (k.hops < 4 && Math.random() < 0.6 && adj[k.to].length) {
        var li = adj[k.to][Math.floor(Math.random() * adj[k.to].length)];
        var next = links[li].a === k.to ? links[li].b : links[li].a;
        k.from = k.to; k.to = next; k.t = 0; k.hops += 1;
      } else { packets.splice(p, 1); }
    }
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);
    ctx.lineWidth = 1;
    for (var i = 0; i < links.length; i++) {
      var A = nodes[links[i].a], B = nodes[links[i].b];
      var dx = A.x - B.x, dy = A.y - B.y, d = Math.sqrt(dx * dx + dy * dy);
      var alpha = Math.max(0.04, 0.2 - d / 1400);
      ctx.strokeStyle = 'rgba(' + CYAN + ',' + alpha.toFixed(3) + ')';
      ctx.beginPath(); ctx.moveTo(A.x, A.y); ctx.lineTo(B.x, B.y); ctx.stroke();
    }
    for (var p = 0; p < packets.length; p++) {
      var k = packets[p], F = nodes[k.from], T = nodes[k.to];
      var x = F.x + (T.x - F.x) * k.t, y = F.y + (T.y - F.y) * k.t;
      var tail = Math.max(0, k.t - 0.12);
      var tx = F.x + (T.x - F.x) * tail, ty = F.y + (T.y - F.y) * tail;
      var g = ctx.createLinearGradient(tx, ty, x, y);
      g.addColorStop(0, 'rgba(' + k.color + ',0)');
      g.addColorStop(1, 'rgba(' + k.color + ',0.9)');
      ctx.strokeStyle = g; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(x, y); ctx.stroke();
      ctx.fillStyle = 'rgba(' + k.color + ',1)';
      ctx.beginPath(); ctx.arc(x, y, k.threat ? 2.4 : 1.8, 0, Math.PI * 2); ctx.fill();
    }
    ctx.lineWidth = 1;
    for (var j = 0; j < nodes.length; j++) {
      var n = nodes[j];
      if (n.shield) {
        ctx.strokeStyle = 'rgba(' + GREEN + ',0.55)';
        ctx.beginPath(); ctx.arc(n.x, n.y, n.r + 4, 0, Math.PI * 2); ctx.stroke();
        ctx.fillStyle = 'rgba(' + GREEN + ',0.9)';
        if (n.pulse > 0) {
          var rr = n.r + 4 + (1 - n.pulse) * 22;
          ctx.strokeStyle = 'rgba(' + (n.pulse > 0.5 ? AMBER : GREEN) + ',' + (n.pulse * 0.8).toFixed(3) + ')';
          ctx.lineWidth = 1.5;
          ctx.beginPath(); ctx.arc(n.x, n.y, rr, 0, Math.PI * 2); ctx.stroke();
          ctx.lineWidth = 1;
        }
      } else {
        ctx.fillStyle = 'rgba(' + CYAN + ',0.65)';
      }
      ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2); ctx.fill();
    }
  }

  function frame(now) {
    raf = 0;
    var dt = Math.min(48, now - (last || now));
    last = now;
    step(dt, now);
    draw();
    if (onScreen && !document.hidden) raf = requestAnimationFrame(frame);
  }
  function play() { if (!raf && !reduce && onScreen && !document.hidden) { last = 0; raf = requestAnimationFrame(frame); } }
  function stop() { if (raf) { cancelAnimationFrame(raf); raf = 0; } }

  function staticFrame() {
    for (var i = 0; i < 14; i++) spawn();
    packets.forEach(function (k) { k.t = Math.random() * 0.9; });
    step(0, performance.now());
    draw();
  }

  build();
  if (reduce) { staticFrame(); } else { play(); }

  var resizeTimer = 0;
  window.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { stop(); build(); if (reduce) staticFrame(); else play(); }, 160);
  });
  document.addEventListener('visibilitychange', function () { if (document.hidden) stop(); else play(); });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (en) { onScreen = en[0].isIntersecting; if (onScreen) play(); else stop(); }).observe(canvas);
  }
})();
