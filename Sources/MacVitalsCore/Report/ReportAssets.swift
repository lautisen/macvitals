// Inline CSS and JS for the self-contained HTML report. No external requests: the report
// must render offline, from an email attachment or a SharePoint preview.
enum ReportAssets {
    static let css = #"""
    :root {
      color-scheme: light;
      --page: #f9f9f7; --surface: #fcfcfb; --ink: #0b0b0b; --ink-2: #52514e; --muted: #6f6d68;
      --grid: #e1e0d9; --axis: #c3c2b7; --border: rgba(11,11,11,.10);
      --s1: #2a78d6; --s2: #eb6834; --s3: #1baf7a;
      --good: #0ca30c; --good-ink: #006300; --warning: #fab219; --critical: #d03b3b; --info: #2a78d6;
      --font: system-ui, -apple-system, "Segoe UI", sans-serif;
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-theme="light"]) {
        color-scheme: dark;
        --page: #0d0d0d; --surface: #1a1a19; --ink: #ffffff; --ink-2: #c3c2b7; --muted: #898781;
        --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,.10);
        --s1: #3987e5; --s2: #d95926; --s3: #199e70; --good-ink: #0ca30c; --info: #3987e5;
      }
    }
    :root[data-theme="dark"] {
      color-scheme: dark;
      --page: #0d0d0d; --surface: #1a1a19; --ink: #ffffff; --ink-2: #c3c2b7; --muted: #898781;
      --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,.10);
      --s1: #3987e5; --s2: #d95926; --s3: #199e70; --good-ink: #0ca30c; --info: #3987e5;
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--page); color: var(--ink); font: 15px/1.5 var(--font); }
    .report { max-width: 1040px; margin: 0 auto; padding: 32px 16px 48px; display: grid; gap: 20px; }
    header.top { display: grid; gap: 6px; }
    .eyebrow { font-size: 13px; color: var(--muted); letter-spacing: .02em; }
    h1 { margin: 0; font-size: 28px; line-height: 1.2; }
    h2 { margin: 0 0 12px; font-size: 17px; }
    .meta { color: var(--ink-2); font-size: 14px; display: flex; flex-wrap: wrap; gap: 4px 16px; }
    .badge { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 999px;
             border: 1px solid var(--border); color: var(--ink-2); vertical-align: middle; margin-left: 8px; }
    .card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 20px; min-width: 0; }
    .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
    .tile { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 14px 16px; }
    .tile .label { font-size: 13px; color: var(--ink-2); }
    .tile .value { font-size: 24px; font-weight: 600; line-height: 1.3; }
    .tile .sub { font-size: 12px; color: var(--muted); }
    .insights { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
    .insights li { display: grid; grid-template-columns: 22px 1fr; gap: 10px; align-items: start; }
    .insights .icon { width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center;
                      font-size: 13px; font-weight: 700; color: #fff; }
    .icon.critical { background: var(--critical); } .icon.warning { background: var(--warning); color: #0b0b0b; }
    .icon.info { background: var(--info); } .icon.ok { background: var(--good); }
    .insights strong { display: block; }
    .insights span { color: var(--ink-2); font-size: 14px; }
    .sev { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); margin-left: 6px; }
    .chart { width: 100%; height: auto; display: block; overflow: visible; touch-action: none; }
    .chart text { font: 12px var(--font); font-variant-numeric: tabular-nums; fill: var(--muted); }
    .grid { stroke: var(--grid); stroke-width: 1; }
    .line { fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
    .line.s1 { stroke: var(--s1); } .line.s2 { stroke: var(--s2); } .line.s3 { stroke: var(--s3); }
    .dot { stroke: var(--surface); stroke-width: 2; } .dot.s1 { fill: var(--s1); } .dot.s2 { fill: var(--s2); } .dot.s3 { fill: var(--s3); }
    .cross { stroke: var(--axis); stroke-width: 1; }
    .legend { display: flex; flex-wrap: wrap; gap: 6px 18px; font-size: 13px; color: var(--ink-2); margin-top: 8px; }
    .key { display: inline-block; width: 14px; height: 3px; border-radius: 2px; margin-right: 6px; vertical-align: middle; }
    .key.s1 { background: var(--s1); } .key.s2 { background: var(--s2); } .key.s3 { background: var(--s3); }
    .charts { display: grid; gap: 20px; }
    @media (max-width: 520px) { h1 { font-size: 22px; } .chart text { font-size: 18px; } }
    .chart-head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
    .chart-head .now { font-size: 13px; color: var(--muted); }
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--grid); white-space: nowrap; }
    th { font-size: 12px; color: var(--muted); font-weight: 600; }
    td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
    .note, .empty { margin: 0; color: var(--ink-2); font-size: 14px; max-width: 75ch; }
    footer { color: var(--muted); font-size: 13px; display: grid; gap: 4px; }
    footer a { color: inherit; }
    #tip { position: fixed; pointer-events: none; z-index: 10; background: var(--surface); color: var(--ink);
           border: 1px solid var(--border); border-radius: 8px; padding: 8px 10px; font-size: 13px;
           box-shadow: 0 4px 16px rgba(0,0,0,.12); display: none; gap: 3px; min-width: 140px; }
    #tip .t { color: var(--muted); font-size: 12px; }
    #tip .r { display: flex; justify-content: space-between; gap: 12px; font-variant-numeric: tabular-nums; }
    @media print { #tip { display: none !important; } .card, .tile { break-inside: avoid; } }
    """#

    /// Crosshair + tooltip for every `svg.line-chart`, reading the series embedded in `data-chart`.
    static let js = #"""
    (function () {
      var tip = document.getElementById('tip');
      var fmt = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
      var nf = new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 });
      function nearest(points, t) {
        var lo = 0, hi = points.length - 1;
        while (hi - lo > 1) { var mid = (lo + hi) >> 1; if (points[mid][0] < t) lo = mid; else hi = mid; }
        return Math.abs(points[lo][0] - t) <= Math.abs(points[hi][0] - t) ? points[lo] : points[hi];
      }
      document.querySelectorAll('svg.line-chart').forEach(function (svg) {
        var d = JSON.parse(svg.dataset.chart), cross = svg.querySelector('.cross'), dots = svg.querySelectorAll('.dot');
        function off() { tip.style.display = 'none'; cross.setAttribute('visibility', 'hidden'); dots.forEach(function (c) { c.setAttribute('visibility', 'hidden'); }); }
        function move(ev) {
          var box = svg.getBoundingClientRect(), x = (ev.clientX - box.left) * d.w / box.width;
          if (x < d.ml || x > d.ml + d.pw) { off(); return; }
          var t = d.t0 + (x - d.ml) / d.pw * (d.t1 - d.t0), shown = false, rows = '';
          d.s.forEach(function (s, i) {
            if (!s.p.length) return;
            var p = nearest(s.p, t), dot = dots[i];
            if (Math.abs(p[0] - t) > d.gap) { dot.setAttribute('visibility', 'hidden'); return; }
            var px = d.ml + (p[0] - d.t0) / (d.t1 - d.t0) * d.pw, py = d.mt + d.ph - Math.min(Math.max(p[1], 0), d.top) / d.top * d.ph;
            dot.setAttribute('cx', px); dot.setAttribute('cy', py); dot.setAttribute('visibility', 'visible');
            if (!shown) { cross.setAttribute('x1', px); cross.setAttribute('x2', px); cross.setAttribute('visibility', 'visible'); tip.innerHTML = ''; shown = true; t = p[0]; }
            rows += '<div class="r"><span>' + s.n.replace(/[&<>]/g, function (c) { return {'&':'&amp;','<':'&lt;','>':'&gt;'}[c]; }) + '</span><b>' + nf.format(p[1]) + ' ' + d.u + '</b></div>';
          });
          if (!shown) {
            cross.setAttribute('visibility', 'hidden');
            rows = '<div class="r"><span>No data: Mac asleep or off</span></div>';
          }
          tip.innerHTML = '<div class="t">' + fmt.format(new Date(t)) + '</div>' + rows;
          tip.style.display = 'grid';
          var tx = ev.clientX + 14, ty = ev.clientY + 14, w = tip.offsetWidth, h = tip.offsetHeight;
          if (tx + w > window.innerWidth - 8) tx = ev.clientX - w - 14;
          if (ty + h > window.innerHeight - 8) ty = ev.clientY - h - 14;
          tip.style.left = tx + 'px'; tip.style.top = ty + 'px';
        }
        svg.addEventListener('pointermove', move);
        svg.addEventListener('pointerdown', move);
        svg.addEventListener('pointerleave', off);
      });
    })();
    """#
}
