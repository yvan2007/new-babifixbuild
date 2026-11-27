/* ============================================================================
   BABIFIX Admin Pro · Interactions, Transcription Drawer, Smart Matching & Live Sync
   ============================================================================ */
(function () {
  "use strict";

  function escHtml(v) {
    return String(v == null ? "" : v)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function parseNum(v, fallback) {
    var s = String(v == null ? "" : v).replace(/\s+/g, "").replace(",", ".");
    var n = Number(s);
    return isFinite(n) ? n : (fallback != null ? fallback : 0);
  }

  function fmtMoney(n) {
    var num = parseNum(n, 0);
    return Math.round(num).toLocaleString("fr-FR") + " FCFA";
  }

  function getCsrfToken() {
    var m = document.cookie.match(/csrftoken=([^;]+)/);
    if (m) return decodeURIComponent(m[1]);
    var inp = document.querySelector('input[name="csrfmiddlewaretoken"]');
    return inp ? inp.value : "";
  }

  // --------------------------------------------------------------------------
  // 1. Animation fluide des compteurs KPI (respecte prefers-reduced-motion)
  // --------------------------------------------------------------------------
  function animateKpiCounters() {
    var els = document.querySelectorAll("[data-count-to]");
    if (!els.length) return;
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return;
    }
    els.forEach(function (el) {
      if (el.dataset.counted === "1") return;
      el.dataset.counted = "1";
      var target = parseFloat(el.getAttribute("data-count-to"));
      if (!isFinite(target) || target <= 0) return;
      var suffix = el.getAttribute("data-count-suffix") || "";
      var decimals = parseInt(el.getAttribute("data-count-decimals") || "0", 10);
      var currencyEl = el.querySelector(".currency");
      var textTarget = currencyEl ? el.firstChild : null;
      var start = performance.now();
      var dur = 520;
      function tick(now) {
        var p = Math.min(1, (now - start) / dur);
        var eased = 1 - Math.pow(1 - p, 3);
        var cur = target * eased;
        var valStr = decimals > 0 ? cur.toFixed(decimals) : Math.round(cur).toLocaleString("fr-FR");
        if (currencyEl && textTarget && textTarget.nodeType === 3) {
          textTarget.nodeValue = valStr + " ";
        } else if (currencyEl) {
          el.textContent = "";
          el.appendChild(document.createTextNode(valStr + " "));
          el.appendChild(currencyEl);
        } else {
          el.textContent = valStr + suffix;
        }
        if (p < 1) requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    });
  }

  // --------------------------------------------------------------------------
  // 2. Slide-Over Drawer : Transcription complete de reservation
  // --------------------------------------------------------------------------
  window.openResaTranscription = async function (reference) {
    var drawer = document.getElementById("bx-transcription-drawer");
    var backdrop = document.getElementById("bx-drawer-backdrop");
    var body = document.getElementById("bx-drawer-body");
    var titleEl = document.getElementById("bx-drawer-title");
    var subEl = document.getElementById("bx-drawer-sub");
    if (!drawer || !body) return;

    titleEl.textContent = "Transcription " + reference;
    subEl.textContent = "Chargement du dossier complet et analyse algorithmique...";
    body.innerHTML = '<div class="bx-drawer-section"><p>Chargement en cours...</p></div>';
    backdrop.classList.add("open");
    drawer.classList.add("open");
    drawer.setAttribute("aria-hidden", "false");

    try {
      var resp = await fetch("/api/admin/reservations/" + encodeURIComponent(reference) + "/transcription/");
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      var data = await resp.json();
      renderTranscriptionDrawer(data);
    } catch (err) {
      body.innerHTML =
        '<div class="bx-drawer-section"><h4>Erreur de chargement</h4><p>Impossible de charger la transcription (' +
        escHtml(err.message) +
        ").</p></div>";
    }
  };

  window.closeResaTranscription = function () {
    var drawer = document.getElementById("bx-transcription-drawer");
    var backdrop = document.getElementById("bx-drawer-backdrop");
    if (drawer) {
      drawer.classList.remove("open");
      drawer.setAttribute("aria-hidden", "true");
    }
    if (backdrop) backdrop.classList.remove("open");
  };

  function renderTranscriptionDrawer(data) {
    var r = data.reservation || {};
    var body = document.getElementById("bx-drawer-body");
    var titleEl = document.getElementById("bx-drawer-title");
    var subEl = document.getElementById("bx-drawer-sub");
    if (!body) return;

    titleEl.textContent = r.reference + " · " + (r.title || "Intervention");
    subEl.textContent = "Statut : " + (r.statut || "") + " · Creee le " + (r.created_at || "");

    var html = [];

    html.push(
      '<div class="bx-privacy-lock">' +
        "<span>&#128274;</span>" +
        "<span>" +
        escHtml(data.privacy_notice || "Messagerie privee chiffree non exposee.") +
        "</span>" +
      "</div>"
    );

    // Resume dossier
    html.push(
      '<div class="bx-drawer-section">' +
        '<h4>Identite, Lieu &amp; Conditions</h4>' +
        '<div class="bx-kv-grid">' +
        '<div class="bx-kv-item"><span>Client</span><strong>' + escHtml(r.client || "N/A") + "</strong></div>" +
        '<div class="bx-kv-item"><span>Prestataire</span><strong>' + escHtml(r.prestataire || "A affecter") + "</strong></div>" +
        '<div class="bx-kv-item"><span>Montant</span><strong class="tabular-nums">' + fmtMoney(r.montant) + "</strong></div>" +
        '<div class="bx-kv-item"><span>Verse / Escrow</span><strong class="tabular-nums">' + fmtMoney(r.montant_verse) + (r.funds_released ? " (Libere)" : " (En cours)") + "</strong></div>" +
        '<div class="bx-kv-item"><span>Mode paiement</span><strong>' + escHtml(r.payment_type || "ESPECES") + (r.mobile_money_operator ? " (" + escHtml(r.mobile_money_operator) + ")" : "") + "</strong></div>" +
        '<div class="bx-kv-item"><span>Caution visite</span><strong>' + (r.caution_payee ? "Payee (" + fmtMoney(r.caution_montant) + ")" : "Non requise") + "</strong></div>" +
        '<div class="bx-kv-item"><span>Ville / Quartier</span><strong>' + escHtml(r.address_ville || "-") + " · " + escHtml(r.address_quartier || "-") + "</strong></div>" +
        '<div class="bx-kv-item"><span>Disponibilites</span><strong>' + escHtml(r.disponibilites_client || "Non precisees") + "</strong></div>" +
        "</div>" +
        (r.description_probleme
          ? '<p style="margin:10px 0 0;font-size:13px;"><strong>Besoin client :</strong> ' + escHtml(r.description_probleme) + "</p>"
          : "") +
        '<div style="margin-top:12px;display:flex;gap:8px;flex-wrap:wrap;">' +
        '<a class="bx-btn-ghost" href="' + escHtml(r.bon_commande_url) + '" target="_blank" rel="noopener">Bon de commande PDF</a>' +
        (r.is_urgent ? '<span class="bx-pill bx-pill--danger">Urgence signalee</span>' : "") +
        (r.visite_suspecte ? '<span class="bx-pill bx-pill--danger">Radar : visite suspecte</span>' : "") +
        "</div>" +
      "</div>"
    );

    // Smart Matching Suggestions
    var matches = data.smart_matches || [];
    if (matches.length) {
      var mCards = matches
        .map(function (m, idx) {
          var reasonsHtml = (m.reasons || [])
            .map(function (rs) { return '<span class="bx-reason-chip">' + escHtml(rs) + "</span>"; })
            .join("");
          return (
            '<div class="bx-match-card">' +
              '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;">' +
                "<strong>#" + (idx + 1) + " " + escHtml(m.nom) + "</strong>" +
                '<span class="bx-pill bx-pill--info tabular-nums">' + Math.round(m.score) + " pts</span>" +
              "</div>" +
              '<div style="font-size:12px;color:var(--bx-muted);">' +
                escHtml(m.specialite) + " · " + escHtml(m.ville || "Abidjan") +
                (m.distance_km != null ? " · " + m.distance_km + " km" : "") +
                " · Comm. " + m.commission_pct + "%" +
              "</div>" +
              '<div class="bx-reasons">' + reasonsHtml + "</div>" +
              '<div style="display:flex;justify-content:flex-end;margin-top:4px;">' +
                '<button type="button" class="bx-btn-accent js-smart-assign-btn" data-ref="' +
                escHtml(r.reference) +
                '" data-pid="' +
                Number(m.provider_id || 0) +
                '">Affecter cet artisan</button>' +
              "</div>" +
            "</div>"
          );
        })
        .join("");

      html.push(
        '<div class="bx-drawer-section">' +
          "<h4>Recommandations Smart Matching (Top 3 reel)</h4>" +
          '<div style="display:flex;flex-direction:column;gap:10px;">' +
          mCards +
          "</div>" +
        "</div>"
      );
    }

    // Chronologie statuts
    var hist = data.history || [];
    var histHtml = hist.length
      ? '<ul class="bx-timeline">' +
        hist
          .map(function (h) {
            return (
              "<li>" +
                '<div class="bx-timeline-time tabular-nums">' + escHtml(h.created_at) + " · " + escHtml(h.changed_by) + "</div>" +
                "<div><strong>" + (h.old_status ? escHtml(h.old_status) + " &rarr; " : "") + escHtml(h.new_status) + "</strong></div>" +
                (h.comment ? '<div style="font-size:12px;color:var(--bx-muted);">' + escHtml(h.comment) + "</div>" : "") +
              "</li>"
            );
          })
          .join("") +
        "</ul>"
      : '<p style="font-size:13px;color:var(--bx-muted);margin:0;">Aucune transition enregistree pour le moment.</p>';
    html.push('<div class="bx-drawer-section"><h4>Chronologie &amp; Transitions</h4>' + histHtml + "</div>");

    // Devis & Audit SmartDevisAdvisor
    var devis = data.devis || [];
    if (devis.length) {
      var dHtml = devis
        .map(function (d) {
          var badgeCls = d.coherence && d.coherence.is_anomaly ? "bx-pill--warn" : "bx-pill--ok";
          var badgeTxt = d.coherence ? d.coherence.label || (d.coherence.is_anomaly ? "Prix atypique" : "Coherent marche") : "Verifie";
          var linesHtml = (d.lignes || [])
            .map(function (lg) {
              return (
                "<tr><td>" + escHtml(lg.description) + "</td>" +
                '<td class="tabular-nums">' + lg.quantite + " " + escHtml(lg.unite || "") + "</td>" +
                '<td class="tabular-nums" style="text-align:right;">' + fmtMoney(lg.total) + "</td></tr>"
              );
            })
            .join("");
          return (
            '<div style="padding:10px;border:1px solid var(--bx-border);border-radius:10px;margin-bottom:10px;">' +
              '<div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:6px;margin-bottom:6px;">' +
                "<strong>" + escHtml(d.reference) + " (" + escHtml(d.statut) + ")</strong>" +
                '<span class="bx-pill ' + badgeCls + '">' + escHtml(badgeTxt) + "</span>" +
              "</div>" +
              '<div style="font-size:12.5px;color:var(--bx-muted);margin-bottom:8px;">' +
                "Total : <strong class='tabular-nums'>" + fmtMoney(d.total_ttc) + "</strong> · Comm (" + d.commission_rate + "%) : " + fmtMoney(d.commission_montant) +
              "</div>" +
              (linesHtml
                ? '<div class="table-wrap"><table class="data-table"><thead><tr><th>Poste</th><th>Qte</th><th style="text-align:right;">Total</th></tr></thead><tbody>' + linesHtml + "</tbody></table></div>"
                : "") +
            "</div>"
          );
        })
        .join("");
      html.push('<div class="bx-drawer-section"><h4>Devis &amp; Audit Prix</h4>' + dHtml + "</div>");
    }

    // Paiements & Appels LiveKit
    var pays = data.payments || [];
    var calls = data.calls || [];
    if (pays.length || calls.length) {
      var pRows = pays
        .map(function (p) {
          return (
            "<tr><td><code>" + escHtml(p.reference) + '</code></td><td class="tabular-nums">' +
            fmtMoney(p.montant) + "</td><td>" + escHtml(p.etat) + "</td><td>" + escHtml(p.created_at) + "</td></tr>"
          );
        })
        .join("");
      var cRows = calls
        .map(function (c) {
          return (
            "<li><strong>" + escHtml(c.kind) + "</strong> (" + escHtml(c.status) + ") · " +
            escHtml(c.caller) + " &rarr; " + escHtml(c.callee) + " · " + c.duration_seconds + "s · " + escHtml(c.started_at) + "</li>"
          );
        })
        .join("");
      html.push(
        '<div class="bx-drawer-section">' +
          "<h4>Paiements &amp; Journal Appels LiveKit</h4>" +
          (pRows
            ? '<div class="table-wrap"><table class="data-table"><thead><tr><th>Ref</th><th>Montant</th><th>Etat</th><th>Date</th></tr></thead><tbody>' + pRows + "</tbody></table></div>"
            : '<p style="font-size:12.5px;color:var(--bx-muted);">Aucun paiement.</p>') +
          (cRows ? '<ul style="margin:10px 0 0;padding-left:18px;font-size:12.5px;">' + cRows + "</ul>" : "") +
        "</div>"
      );
    }

    body.innerHTML = html.join("");
  }

  window.smartAssignFromDrawer = async function (reference, providerId) {
    try {
      var resp = await fetch("/api/admin/reservations/" + encodeURIComponent(reference) + "/assign/", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRFToken": getCsrfToken(),
        },
        body: JSON.stringify({ provider_id: providerId }),
      });
      var out = await resp.json();
      if (!resp.ok || !out.ok) {
        alert(out.message || "Erreur lors de l'affectation.");
        return;
      }
      if (window.showBabifixToast) {
        window.showBabifixToast("success", "Affectation Smart Matching", "Reservation " + reference + " affectee a " + out.assigned_provider.nom);
      }
      window.openResaTranscription(reference);
    } catch (e) {
      alert("Erreur reseau lors de l'affectation.");
    }
  };

  // --------------------------------------------------------------------------
  // 3. Simulateur Smart Matching (section=reservations)
  // --------------------------------------------------------------------------
  window.runSmartMatchSim = async function () {
    var box = document.getElementById("bx-match-sim-results");
    if (!box) return;
    box.innerHTML = '<p style="font-size:13px;color:var(--bx-muted);">Calcul multi-criteres en cours...</p>';

    var params = new URLSearchParams();
    var qEl = document.getElementById("bx-sim-q");
    var catEl = document.getElementById("bx-sim-cat");
    var cityEl = document.getElementById("bx-sim-ville");
    var budgetEl = document.getElementById("bx-sim-budget");
    var resEl = document.getElementById("bx-sim-resref");
    var latEl = document.getElementById("bx-sim-lat");
    var lonEl = document.getElementById("bx-sim-lon");

    if (resEl && resEl.value.trim()) params.set("reservation_ref", resEl.value.trim());
    if (qEl && qEl.value.trim()) params.set("q", qEl.value.trim());
    if (catEl && catEl.value) params.set("category_id", catEl.value);
    if (cityEl && cityEl.value.trim()) params.set("ville", cityEl.value.trim());
    if (budgetEl && budgetEl.value.trim()) params.set("price_max", budgetEl.value.trim());
    if (latEl && latEl.value.trim()) params.set("lat", latEl.value.trim());
    if (lonEl && lonEl.value.trim()) params.set("lon", lonEl.value.trim());

    try {
      var resp = await fetch("/api/admin/matching/simulate/?" + params.toString());
      var data = await resp.json();
      if (!resp.ok || !data.ok) {
        box.innerHTML = '<p style="color:var(--bx-danger);">Erreur simulateur matching.</p>';
        return;
      }
      if (!data.results || !data.results.length) {
        box.innerHTML = '<p style="color:var(--bx-muted);">Aucun prestataire valide disponible pour ces criteres.</p>';
        return;
      }
      var resRefVal = resEl && resEl.value.trim() ? resEl.value.trim() : "";
      box.innerHTML = data.results
        .map(function (it) {
          var b = it.breakdown || {};
          var pct = Math.min(100, Math.round(it.score));
          var reasons = (it.reasons || [])
            .map(function (rs) { return '<span class="bx-reason-chip">' + escHtml(rs) + "</span>"; })
            .join("");
          var assignBtn = resRefVal
            ? '<button type="button" class="bx-btn-accent js-smart-assign-btn" data-ref="' +
              escHtml(resRefVal) +
              '" data-pid="' +
              Number(it.provider_id || 0) +
              '">Affecter a ' +
              escHtml(resRefVal) +
              "</button>"
            : "";
          return (
            '<div class="bx-match-card">' +
              '<div style="display:flex;justify-content:space-between;align-items:center;">' +
                "<strong>#" + it.rank + " " + escHtml(it.nom) + "</strong>" +
                '<span class="bx-pill bx-pill--info tabular-nums">' + Math.round(it.score) + " / 100+</span>" +
              "</div>" +
              '<div class="bx-score-meter"><span style="width:' + pct + '%;"></span></div>' +
              '<div style="font-size:12px;color:var(--bx-muted);">' +
                escHtml(it.specialite) + " · " + escHtml(it.ville || "-") +
                (it.distance_km != null ? " · " + it.distance_km + " km" : "") +
                " · Tier " + escHtml(it.tier).toUpperCase() + " (" + it.commission_pct + "%)" +
              "</div>" +
              '<div style="font-size:11.5px;color:var(--bx-muted);" class="tabular-nums">' +
                "Prox " + (b.proximity || 0) + "% · Note " + (b.rating || 0) + "% · Dispo " + (b.availability || 0) + "% · Fiab " + (b.reliability || 0) + "% · Prix " + (b.price_fit || 0) + "%" +
              "</div>" +
              '<div class="bx-reasons">' + reasons + "</div>" +
              (assignBtn ? '<div style="margin-top:4px;display:flex;justify-content:flex-end;">' + assignBtn + "</div>" : "") +
            "</div>"
          );
        })
        .join("");
    } catch (e) {
      box.innerHTML = '<p style="color:var(--bx-danger);">Erreur reseau simulateur.</p>';
    }
  };

  // --------------------------------------------------------------------------
  // 4. Carte Wallet 3D interactive Recto/Verso par palier (section=finances)
  // --------------------------------------------------------------------------
  window.toggleWalletFlip = function (forceFront) {
    var flipper = document.getElementById("bx-wallet-flipper");
    if (!flipper) return;
    if (forceFront === true) {
      flipper.classList.remove("is-flipped");
    } else {
      flipper.classList.toggle("is-flipped");
    }
  };

  window.selectWalletTier = function (tier) {
    var card = document.getElementById("bx-wallet-3d");
    if (!card) return;
    // Toujours revenir au recto pour montrer la carte du palier choisi
    window.toggleWalletFlip(true);

    card.classList.remove("bx-wallet-card--standard", "bx-wallet-card--silver", "bx-wallet-card--gold");
    card.classList.add("bx-wallet-card--" + tier);

    document.querySelectorAll("[data-wallet-tier-btn]").forEach(function (b) {
      b.classList.toggle("active", b.getAttribute("data-wallet-tier-btn") === tier);
    });

    var title = document.getElementById("bx-w-title");
    var comm = document.getElementById("bx-w-comm");
    var solde = document.getElementById("bx-w-solde");
    var meta = document.getElementById("bx-w-meta");
    var backTier = document.getElementById("bx-w-back-tier");

    var d = card.dataset;
    var stdRate = d.stdRate || "18";
    var stdQuota = d.stdQuota || "3";
    var silRate = d.silverRate || "13";
    var silPrice = parseNum(d.silverPrice, 7500);
    var silQuota = d.silverQuota || "15";
    var silBoost = d.silverBoost || "1.3";
    var gldRate = d.goldRate || "8";
    var gldPrice = parseNum(d.goldPrice, 15000);
    var gldBoost = d.goldBoost || "1.6";

    if (tier === "gold") {
      if (title) title.textContent = "BABIFIX PRO GOLD · Elite";
      if (comm) comm.textContent = "Commission " + gldRate + "% · Visibilite x" + gldBoost + " · Devis illimites";
      if (solde) solde.textContent = fmtMoney(d.goldSolde || 0);
      if (meta) meta.textContent = (d.goldCount || "0") + " prestataire(s) actif(s) · " + gldPrice.toLocaleString("fr-FR") + " FCFA/mois";
      if (backTier) backTier.textContent = "PALIER GOLD (" + gldRate + "%) · SEQUESTRE & CANAUX PAYOUT";
    } else if (tier === "silver") {
      if (title) title.textContent = "BABIFIX PRO SILVER · Certifie";
      if (comm) comm.textContent = "Commission " + silRate + "% · Visibilite x" + silBoost + " · " + silQuota + " devis";
      if (solde) solde.textContent = fmtMoney(d.silverSolde || 0);
      if (meta) meta.textContent = (d.silverCount || "0") + " prestataire(s) actif(s) · " + silPrice.toLocaleString("fr-FR") + " FCFA/mois";
      if (backTier) backTier.textContent = "PALIER SILVER (" + silRate + "%) · SEQUESTRE & CANAUX PAYOUT";
    } else {
      if (title) title.textContent = "BABIFIX STANDARD · Base";
      if (comm) comm.textContent = "Commission " + stdRate + "% · Visibilite x1.0 · " + stdQuota + " devis actifs";
      if (solde) solde.textContent = fmtMoney(d.stdSolde || 0);
      if (meta) meta.textContent = (d.stdCount || "0") + " prestataire(s) actif(s) · Gratuit";
      if (backTier) backTier.textContent = "PALIER STANDARD (" + stdRate + "%) · SEQUESTRE & CANAUX PAYOUT";
    }
  };

  // --------------------------------------------------------------------------
  // 5. Apercu audience Push FCM en temps reel
  // --------------------------------------------------------------------------
  window.updatePushAudiencePreview = async function () {
    var sel = document.getElementById("bx-push-role");
    var preview = document.getElementById("bx-push-reach-preview");
    if (!sel || !preview) return;
    try {
      var resp = await fetch("/api/admin/push-stats/?role=" + encodeURIComponent(sel.value || ""));
      if (!resp.ok) return;
      var data = await resp.json();
      preview.textContent =
        "Audience estimee : " +
        data.estimated_users +
        " compte(s) · " +
        data.estimated_fcm_devices +
        " appareil(s) FCM joignables";
    } catch (e) {}
  };

  // Filtrage live des cartes (Kanban, CRM, Inbox, Newsroom)
  window.babifixFilterCards = function (query, containerSelector) {
    var root = document.querySelector(containerSelector || ".bx-kboard, .bx-crm-zones, .bx-inbox-split, .bx-news-groups");
    if (!root) return;
    var q = String(query || "").trim().toLowerCase();
    var cards = root.querySelectorAll(".bx-kcard, .bx-crm-card, .bx-notif-card, .bx-news-card");
    cards.forEach(function (card) {
      var haystack = (card.getAttribute("data-search") || card.textContent || "").toLowerCase();
      var match = !q || haystack.indexOf(q) !== -1;
      card.style.display = match ? "" : "none";
    });
    // Recalculer les compteurs visibles de colonnes/zones si applicable
    root.querySelectorAll(".bx-klane, .bx-crm-zone, .bx-inbox-pane, .bx-news-section").forEach(function (lane) {
      var badge = lane.querySelector("[data-lane-count]");
      if (!badge) return;
      var total = lane.querySelectorAll(".bx-kcard, .bx-crm-card, .bx-notif-card, .bx-news-card");
      var visible = 0;
      total.forEach(function (c) {
        if (c.style.display !== "none") visible += 1;
      });
      badge.textContent = q ? (visible + "/" + total.length) : String(total.length);
    });
  };

  // Affichage / masquage des colonnes vides sur les tableaux Kanban
  window.babifixToggleEmptyLanes = function (btn) {
    var container = (btn && btn.closest(".card, main, body")) || document;
    var board = container.querySelector(".bx-kboard") || document.querySelector(".bx-kboard");
    if (!board) return;
    var emptyLanes = board.querySelectorAll(".bx-klane--compact-empty");
    var isHiding = board.getAttribute("data-hide-empty") === "1";
    var nextHide = !isHiding;
    board.setAttribute("data-hide-empty", nextHide ? "1" : "0");
    emptyLanes.forEach(function (lane) {
      lane.classList.toggle("bx-klane--hidden-empty", nextHide);
    });
    if (btn) {
      btn.classList.toggle("is-active", !nextHide);
      btn.setAttribute("aria-pressed", String(!nextHide));
      var labelEl = btn.querySelector("[data-toggle-label]");
      if (labelEl) {
        labelEl.textContent = nextHide ? "Afficher colonnes vides" : "Masquer colonnes vides";
      }
    }
  };

  // Auto-reveler les colonnes vides pendant un drag-and-drop pour autoriser le depot
  document.addEventListener("dragstart", function (e) {
    if (!e.target || !e.target.classList || !e.target.classList.contains("kanban-card")) return;
    document.querySelectorAll(".bx-kboard[data-hide-empty='1']").forEach(function (board) {
      board.setAttribute("data-temp-revealed", "1");
      board.querySelectorAll(".bx-klane--compact-empty.bx-klane--hidden-empty").forEach(function (lane) {
        lane.classList.remove("bx-klane--hidden-empty");
      });
    });
  });

  document.addEventListener("dragend", function () {
    document.querySelectorAll(".bx-kboard[data-temp-revealed='1']").forEach(function (board) {
      board.removeAttribute("data-temp-revealed");
      if (board.getAttribute("data-hide-empty") === "1") {
        board.querySelectorAll(".bx-klane--compact-empty").forEach(function (lane) {
          var count = lane.querySelectorAll(".bx-kcard").length;
          if (count === 0) lane.classList.add("bx-klane--hidden-empty");
        });
      }
    });
  });

  // Garde non-perturbateur pour le live WebSocket
  window.babifixShouldAutoRefresh = function () {
    if (localStorage.getItem("babifix-ws-paused") === "1") return false;
    var active = document.activeElement;
    if (active && /^(INPUT|TEXTAREA|SELECT)$/.test(active.tagName)) return false;
    if (document.querySelector(".pay-modal-overlay.open, .bx-drawer.open")) return false;
    return true;
  };

  function initWalletTilt() {
    var card = document.getElementById("bx-wallet-3d");
    if (!card || card.dataset.tiltBound === "1") return;
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    card.dataset.tiltBound = "1";
    card.addEventListener("pointermove", function (ev) {
      var rect = card.getBoundingClientRect();
      if (!rect.width || !rect.height) return;
      var x = (ev.clientX - rect.left) / rect.width;
      var y = (ev.clientY - rect.top) / rect.height;
      var rx = ((0.5 - y) * 7).toFixed(2) + "deg";
      var ry = ((x - 0.5) * 9).toFixed(2) + "deg";
      card.style.setProperty("--rx", rx);
      card.style.setProperty("--ry", ry);
      card.style.setProperty("--mx", Math.round(x * 100) + "%");
      card.style.setProperty("--my", Math.round(y * 100) + "%");
    });
    card.addEventListener("pointerleave", function () {
      card.style.setProperty("--rx", "0deg");
      card.style.setProperty("--ry", "0deg");
    });
  }

  function hoistAdminModals() {
    var overlays = document.querySelectorAll("#section-content .pay-modal-overlay");
    overlays.forEach(function (ov) {
      if (ov.id) {
        document.querySelectorAll("body > #" + ov.id).forEach(function (stale) {
          if (stale !== ov && stale.parentNode) stale.parentNode.removeChild(stale);
        });
      }
      document.body.appendChild(ov);
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    hoistAdminModals();
    animateKpiCounters();
    initWalletTilt();

    var backdrop = document.getElementById("bx-drawer-backdrop");
    if (backdrop) {
      backdrop.addEventListener("click", window.closeResaTranscription);
    }

    var syncBtn = document.getElementById("bx-sync-toggle");
    if (syncBtn) {
      function refreshToggleUI() {
        var paused = localStorage.getItem("babifix-ws-paused") === "1";
        syncBtn.classList.toggle("is-paused", paused);
        syncBtn.textContent = paused ? "Sync en pause" : "Auto-sync actif";
      }
      refreshToggleUI();
      syncBtn.addEventListener("click", function () {
        var paused = localStorage.getItem("babifix-ws-paused") === "1";
        localStorage.setItem("babifix-ws-paused", paused ? "0" : "1");
        refreshToggleUI();
      });
    }

    var pushSel = document.getElementById("bx-push-role");
    if (pushSel) {
      pushSel.addEventListener("change", window.updatePushAudiencePreview);
    }

    document.addEventListener("click", function (ev) {
      var btn = ev.target && ev.target.closest ? ev.target.closest(".js-smart-assign-btn") : null;
      if (!btn) return;
      var ref = btn.getAttribute("data-ref") || "";
      var pid = parseInt(btn.getAttribute("data-pid") || "0", 10);
      if (ref && pid && typeof window.smartAssignFromDrawer === "function") {
        window.smartAssignFromDrawer(ref, pid);
      }
    });
  });

  document.addEventListener("htmx:afterSwap", function () {
    hoistAdminModals();
    animateKpiCounters();
    initWalletTilt();
    if (typeof window.updateParamSimulator === "function") {
      window.updateParamSimulator();
    }
    if (typeof window.bindCategoryPreviewInputs === "function") {
      window.bindCategoryPreviewInputs();
    }
  });
})();
