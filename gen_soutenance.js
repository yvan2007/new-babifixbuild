const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.333 x 7.5
pres.author = "KOUAKOU EBOUHO FRANCK YVAN";
pres.title = "BABIFIX - Soutenance (Cas de recherche)";

// ---- Palette BABIFIX ----
const NAVY = "0B1B34", NAVY2 = "13294B", CYAN = "4CC9F0", ICE = "CADCFC";
const WHITE = "FFFFFF", SLATE = "64748B", INK = "0F172A";
const AMBER = "F59E0B", GREEN = "22C55E", PURPLE = "7C3AED", LIGHT = "F1F5F9", LINE = "E2E8F0";
const HF = "Trebuchet MS", BF = "Calibri";

const shadow = () => ({ type: "outer", color: "0B1B34", blur: 8, offset: 3, angle: 135, opacity: 0.16 });

function motif(slide, n) {
  slide.addShape(pres.shapes.OVAL, { x: 0.55, y: 0.5, w: 0.55, h: 0.55, fill: { color: CYAN } });
  slide.addText(String(n), { x: 0.55, y: 0.5, w: 0.55, h: 0.55, align: "center", valign: "middle", fontFace: HF, bold: true, fontSize: 17, color: NAVY });
}
function title(slide, txt) {
  slide.addText(txt, { x: 1.3, y: 0.5, w: 11.5, h: 0.7, margin: 0, fontFace: HF, bold: true, fontSize: 28, color: NAVY, valign: "middle" });
}
function contentSlide(n, t) {
  const s = pres.addSlide();
  s.background = { color: WHITE };
  motif(s, n); title(s, t);
  return s;
}
function card(slide, x, y, w, h, fill) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: fill || LIGHT }, line: { color: LINE, width: 1 }, shadow: shadow() });
}
let SN = 0;

// =================================================================
// 1 — Page de garde
// =================================================================
(() => {
  const s = pres.addSlide();
  s.background = { color: NAVY };
  s.addShape(pres.shapes.OVAL, { x: 10.7, y: -1.7, w: 4.6, h: 4.6, fill: { color: NAVY2 } });
  s.addShape(pres.shapes.OVAL, { x: 11.9, y: 5.0, w: 3.4, h: 3.4, fill: { color: NAVY2 } });
  s.addText("INSTITUT IVOIRIEN DE TECHNOLOGIE (IIT)  ·  VITIB, GRAND-BASSAM", { x: 0.9, y: 0.55, w: 11.5, h: 0.35, fontFace: HF, fontSize: 12, color: CYAN, charSpacing: 1, bold: true });
  s.addText("Mémoire de fin de cycle — Licence en Génie Logiciel", { x: 0.9, y: 0.95, w: 11.5, h: 0.35, fontFace: BF, fontSize: 13, color: ICE });
  s.addText("BABIFIX", { x: 0.85, y: 1.55, w: 11.5, h: 1.3, margin: 0, fontFace: HF, bold: true, fontSize: 70, color: WHITE });
  s.addShape(pres.shapes.RECTANGLE, { x: 0.95, y: 2.95, w: 1.6, h: 0.07, fill: { color: CYAN } });
  s.addText("Conception et réalisation d'une plateforme numérique de services à domicile en Côte d'Ivoire", { x: 0.9, y: 3.15, w: 10.2, h: 0.95, fontFace: BF, fontSize: 19, color: ICE, lineSpacingMultiple: 1.08 });
  // identity block
  card2(s);
  function card2(s) {
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.9, y: 4.35, w: 7.7, h: 2.35, rectRadius: 0.08, fill: { color: NAVY2 }, line: { color: "1E3A5F", width: 1 } });
    const rows = [
      ["Présenté par", "KOUAKOU EBOUHO FRANCK YVAN"],
      ["Encadrant académique", "M. ANANGAMAN SEDRICK GAËL KOUAGNI"],
      ["Maître de stage (SNDI)", "M. TIÉ Zaouri Narcisse"],
      ["Année académique", "2025 – 2026"],
    ];
    let y = 4.5;
    rows.forEach((r) => {
      s.addText(r[0], { x: 1.15, y, w: 2.9, h: 0.45, fontFace: BF, fontSize: 12.5, color: CYAN, bold: true, valign: "middle" });
      s.addText(r[1], { x: 4.0, y, w: 4.4, h: 0.45, fontFace: BF, fontSize: 13, color: WHITE, valign: "middle" });
      y += 0.53;
    });
  }
  s.addText("Stage effectué à la Société Nationale de Développement Informatique (SNDI) — Département Génie Logiciel", { x: 0.9, y: 6.85, w: 11.5, h: 0.4, fontFace: BF, italic: true, fontSize: 11.5, color: SLATE });
})();

// =================================================================
// 2 — Plan
// =================================================================
(() => {
  const s = contentSlide(2, "Plan de la présentation");
  const items = [
    ["01", "Contexte & justification", "Marché ivoirien des services à domicile"],
    ["02", "Problématique", "Question de recherche"],
    ["03", "État de l'art", "Plateformes existantes & limites"],
    ["04", "Hypothèses & méthodologie", "Démarche de recherche"],
    ["05", "Données & interprétation", "Enquête terrain (Annexe 3)"],
    ["06", "Solution proposée : BABIFIX", "Conception & modélisation UML"],
    ["07", "Architecture & démonstration", "Réalisation technique"],
    ["08", "Validation, limites & perspectives", "Tests, bilan, évolutions"],
  ];
  const colW = 5.6, ch = 1.12, gap = 0.16;
  items.forEach((it, i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 1.3 + col * (colW + 0.45);
    const y = 1.5 + row * (ch + gap);
    card(s, x, y, colW, ch, WHITE);
    s.addText(it[0], { x: x + 0.12, y: y + 0.1, w: 0.95, h: ch - 0.2, align: "center", valign: "middle", fontFace: HF, bold: true, fontSize: 25, color: CYAN });
    s.addText([
      { text: it[1], options: { bold: true, fontSize: 15.5, color: NAVY, breakLine: true } },
      { text: it[2], options: { fontSize: 11.5, color: SLATE } },
    ], { x: x + 1.12, y: y + 0.1, w: colW - 1.25, h: ch - 0.2, valign: "middle", fontFace: BF });
  });
})();

// =================================================================
// 3 — Contexte général
// =================================================================
(() => {
  const s = contentSlide(3, "Contexte général & justification");
  s.addText([
    { text: "Domaine : ", options: { bold: true, color: NAVY } },
    { text: "économie des plateformes numériques appliquée aux services à domicile (plomberie, électricité, ménage, jardinage, garde d'enfants).", options: { color: INK } },
  ], { x: 1.3, y: 1.45, w: 7.1, h: 0.85, fontFace: BF, fontSize: 14.5, lineSpacingMultiple: 1.1 });
  const pts = [
    "Secteur massivement informel : pas de cadre, pas de contrôle qualité.",
    "Le client ne peut pas vérifier la fiabilité de l'intervenant.",
    "Le prestataire honnête peine à se faire connaître et payer.",
    "Paiements en espèces, sans traçabilité ni recours.",
  ];
  s.addText(pts.map((p) => ({ text: p, options: { bullet: { code: "2022" }, color: INK, breakLine: true, paraSpaceAfter: 7 } })),
    { x: 1.35, y: 2.35, w: 7.05, h: 2.3, fontFace: BF, fontSize: 14, lineSpacingMultiple: 1.05 });
  s.addText("Pourtant, un contexte très favorable au numérique : la Côte d'Ivoire est en tête de l'adoption du paiement mobile.", { x: 1.3, y: 4.75, w: 7.1, h: 0.8, fontFace: BF, italic: true, fontSize: 13.5, color: PURPLE, lineSpacingMultiple: 1.1 });
  // Right stats (real, from report)
  const stats = [["+24 M", "comptes Mobile Money actifs", CYAN], ["+70 %", "des adultes paient par téléphone", AMBER], ["4", "opérateurs : Orange · MTN · Moov · Wave", GREEN]];
  let yy = 1.45;
  stats.forEach((st) => {
    card(s, 8.75, yy, 3.95, 1.55, NAVY);
    s.addText(st[0], { x: 8.95, y: yy + 0.12, w: 3.6, h: 0.85, fontFace: HF, bold: true, fontSize: 34, color: st[2] });
    s.addText(st[1], { x: 8.95, y: yy + 0.95, w: 3.6, h: 0.5, fontFace: BF, fontSize: 12, color: ICE });
    yy += 1.7;
  });
  s.addText("Sources : SikaFinance (2024), SocialNetLink (2025), ARTCI / GSMA.", { x: 8.75, y: 6.6, w: 3.95, h: 0.3, fontFace: BF, italic: true, fontSize: 9.5, color: SLATE });
})();

// =================================================================
// 4 — Problématique
// =================================================================
(() => {
  const s = contentSlide(4, "Problématique");
  card(s, 1.3, 1.5, 11.4, 1.7, NAVY);
  s.addText("QUESTION DE RECHERCHE", { x: 1.6, y: 1.7, w: 10.7, h: 0.4, fontFace: HF, bold: true, fontSize: 13, color: CYAN, charSpacing: 1.5 });
  s.addText("« Comment concevoir et réaliser une plateforme numérique capable de mettre en relation, de manière fiable et sécurisée, les clients et les prestataires de services à domicile en Côte d'Ivoire, tout en levant le verrou de la confiance qui caractérise ce marché ? »",
    { x: 1.6, y: 2.05, w: 10.8, h: 1.05, fontFace: BF, fontSize: 15.5, color: WHITE, lineSpacingMultiple: 1.08 });
  s.addText("Trois verrous identifiés", { x: 1.3, y: 3.5, w: 11, h: 0.4, fontFace: HF, bold: true, fontSize: 16, color: NAVY });
  const v = [
    ["Confiance", "Aucune vérification d'identité : le client invite un inconnu chez lui."],
    ["Communication", "Échanges dispersés, sans lien avec une réservation ni historique."],
    ["Paiement", "Carte bancaire inadaptée ; le Mobile Money n'est pas pris en charge."],
  ];
  const cw = 3.66, gap = 0.2;
  v.forEach((e, i) => {
    const x = 1.3 + i * (cw + gap);
    card(s, x, 4.0, cw, 2.35, LIGHT);
    s.addShape(pres.shapes.OVAL, { x: x + 0.25, y: 4.22, w: 0.5, h: 0.5, fill: { color: [CYAN, AMBER, GREEN][i] } });
    s.addText(e[0], { x: x + 0.25, y: 4.85, w: cw - 0.5, h: 0.5, fontFace: HF, bold: true, fontSize: 16, color: NAVY });
    s.addText(e[1], { x: x + 0.25, y: 5.35, w: cw - 0.5, h: 0.9, fontFace: BF, fontSize: 12.5, color: INK, lineSpacingMultiple: 1.05 });
  });
})();

// =================================================================
// 5 — État de l'art
// =================================================================
(() => {
  const s = contentSlide(5, "Revue de littérature & état de l'art");
  s.addText("Comparatif fonctionnel des plateformes disponibles en Côte d'Ivoire :", { x: 1.3, y: 1.42, w: 11, h: 0.35, fontFace: BF, fontSize: 13.5, color: INK });
  const H = (t, c) => ({ text: t, options: { bold: true, color: c === CYAN ? NAVY : WHITE, fill: { color: c }, align: "center" } });
  const rows = [
    [H("Fonctionnalité", NAVY), H("Yako", NAVY), H("OnDjossi", NAVY), H("Gombo", NAVY), H("Mon Artisan", NAVY), H("BABIFIX", CYAN)],
    ["Vérification KYC", "✗", "✗", "✗", "✗", "✓"],
    ["Réservation en ligne", "Partiel", "Partiel", "Partiel", "✗", "✓"],
    ["Cycle de devis", "✗", "✗", "✗", "✗", "✓"],
    ["Chat temps réel", "✗", "✗", "✗", "✗", "✓"],
    ["Paiement Mobile Money", "✗", "✗", "✗", "✗", "✓"],
    ["Paiement sécurisé (séquestre)", "✗", "✗", "✗", "✗", "✓"],
    ["Classement par proximité", "Partiel", "✗", "Partiel", "✗", "✓"],
  ];
  // center align value cells
  const data = rows.map((r, ri) => r.map((c, ci) => {
    if (typeof c === "string") return { text: c, options: { align: ci === 0 ? "left" : "center", color: c === "✓" ? GREEN : (c === "✗" ? SLATE : INK), bold: c === "✓" } };
    return c;
  }));
  s.addTable(data, { x: 1.3, y: 1.8, w: 11.4, colW: [3.4, 1.5, 1.6, 1.5, 1.8, 1.6], rowH: 0.46, fontFace: BF, fontSize: 12, valign: "middle", border: { type: "solid", pt: 1, color: LINE }, fill: { color: WHITE } });
  s.addText([
    { text: "Limite commune : ", options: { bold: true, color: PURPLE } },
    { text: "le déficit de confiance. Les références internationales (TaskRabbit, Thumbtack) valident le modèle, mais reposent sur la carte bancaire — inadaptée au marché ouest-africain.", options: { color: INK } },
  ], { x: 1.3, y: 6.35, w: 11.4, h: 0.8, fontFace: BF, italic: true, fontSize: 12.5, lineSpacingMultiple: 1.05 });
})();

// =================================================================
// 6 — Hypothèses
// =================================================================
(() => {
  const s = contentSlide(6, "Hypothèses de recherche");
  const hyps = [
    ["H1", "Une mise en relation géolocalisée (distance réelle) augmente la confiance et le taux de mise en relation.", CYAN],
    ["H2", "Un paiement séquestre (escrow) via Mobile Money réduit significativement les litiges client–prestataire.", AMBER],
    ["H3", "Une vérification d'identité (KYC) et une interface simple, mobile-first, sont déterminantes pour l'adoption.", GREEN],
  ];
  let y = 1.65;
  hyps.forEach((h) => {
    card(s, 1.3, y, 11.4, 1.5, WHITE);
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 1.55, y: y + 0.25, w: 1.0, h: 1.0, rectRadius: 0.5, fill: { color: h[2] } });
    s.addText(h[0], { x: 1.55, y: y + 0.25, w: 1.0, h: 1.0, align: "center", valign: "middle", fontFace: HF, bold: true, fontSize: 25, color: NAVY });
    s.addText(h[1], { x: 2.85, y: y + 0.2, w: 9.6, h: 1.1, valign: "middle", fontFace: BF, fontSize: 15.5, color: INK, lineSpacingMultiple: 1.1 });
    y += 1.7;
  });
})();

// =================================================================
// 7 — Méthodologie de recherche
// =================================================================
(() => {
  const s = contentSlide(7, "Méthodologie de recherche");
  const blocks = [
    ["Type d'étude", "Démarche mixte : étude documentaire + enquête terrain + conception logicielle.", CYAN],
    ["Population cible", "Clients potentiels et prestataires de services à domicile (Abidjan).", AMBER],
    ["Collecte de données", "Questionnaire en ligne (Google Forms, Annexe 3) + analyse de l'existant.", GREEN],
    ["Conception & validation", "Modélisation UML (PlantUML), puis développement et tests du prototype.", PURPLE],
  ];
  blocks.forEach((b, i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 1.3 + col * 5.75;
    const y = 1.55 + row * 1.75;
    card(s, x, y, 5.45, 1.5, LIGHT);
    s.addShape(pres.shapes.RECTANGLE, { x, y, w: 0.12, h: 1.5, fill: { color: b[2] } });
    s.addText(b[0], { x: x + 0.3, y: y + 0.18, w: 4.9, h: 0.45, fontFace: HF, bold: true, fontSize: 16, color: NAVY });
    s.addText(b[1], { x: x + 0.3, y: y + 0.65, w: 4.95, h: 0.75, fontFace: BF, fontSize: 13, color: INK, lineSpacingMultiple: 1.05 });
  });
  // mini Gantt note
  card(s, 1.3, 5.2, 11.4, 1.35, NAVY);
  s.addText("Projet planifié sur 16 semaines (diagramme de Gantt) :", { x: 1.55, y: 5.32, w: 11, h: 0.35, fontFace: HF, bold: true, fontSize: 13, color: CYAN });
  s.addText("Étude & état de l'art (S1–S3)  →  Analyse des besoins (S3–S5)  →  Modélisation UML (S5–S7)  →  Développement serveur & apps (S7–S13)  →  Paiement & notifications (S12–S14)  →  Tests & rédaction (S14–S16).",
    { x: 1.55, y: 5.7, w: 11, h: 0.75, fontFace: BF, fontSize: 12.5, color: ICE, lineSpacingMultiple: 1.05 });
})();

// =================================================================
// 8 — Données collectées (chart)
// =================================================================
(() => {
  const s = contentSlide(8, "Présentation & analyse des données");
  s.addChart(pres.charts.BAR, [{
    name: "Répondants (%)",
    labels: ["Difficulté à\ntrouver un\nprestataire fiable", "Déjà déçu par\nun service", "Prêts à utiliser\nune application", "Préfèrent le\nMobile Money", "Veulent voir\nles avis"],
    values: [82, 64, 88, 71, 90],
  }], {
    x: 0.9, y: 1.5, w: 7.7, h: 5.2, barDir: "col",
    chartColors: [CYAN], chartArea: { fill: { color: WHITE } },
    catAxisLabelColor: SLATE, valAxisLabelColor: SLATE, catAxisLabelFontSize: 9, valAxisLabelFontSize: 10,
    valGridLine: { color: LINE, size: 0.5 }, catGridLine: { style: "none" },
    showValue: true, dataLabelPosition: "outEnd", dataLabelColor: NAVY, dataLabelFontSize: 11, dataLabelFormatCode: '0"%"',
    showLegend: false, valAxisMaxVal: 100, valAxisMinVal: 0,
  });
  card(s, 9.0, 1.5, 3.7, 5.2, NAVY);
  s.addText("Enseignements", { x: 9.25, y: 1.72, w: 3.2, h: 0.4, fontFace: HF, bold: true, fontSize: 16, color: CYAN });
  s.addText([
    { text: "Fort besoin de fiabilité et de transparence.", options: { bullet: { code: "2022" }, breakLine: true, paraSpaceAfter: 9 } },
    { text: "Forte appétence pour une solution mobile.", options: { bullet: { code: "2022" }, breakLine: true, paraSpaceAfter: 9 } },
    { text: "Mobile Money = moyen de paiement attendu.", options: { bullet: { code: "2022" }, breakLine: true, paraSpaceAfter: 9 } },
    { text: "Les avis / notations guident le choix.", options: { bullet: { code: "2022" } } },
  ], { x: 9.25, y: 2.2, w: 3.25, h: 3.6, fontFace: BF, fontSize: 12.5, color: ICE, lineSpacingMultiple: 1.05 });
  s.addText("⚠ Remplace ces valeurs par tes résultats Google Forms (Annexe 3).", { x: 0.9, y: 6.75, w: 7.7, h: 0.35, fontFace: BF, italic: true, fontSize: 10, color: AMBER });
})();

// =================================================================
// 9 — Interprétation des résultats
// =================================================================
(() => {
  const s = contentSlide(9, "Interprétation des résultats");
  s.addText("Les données confirment la problématique et orientent la conception :", { x: 1.3, y: 1.5, w: 11, h: 0.4, fontFace: BF, fontSize: 14.5, color: INK });
  const items = [
    ["H1 confirmée", "Le besoin de proximité/fiabilité justifie un matching géolocalisé (Haversine, rayon adaptatif).", GREEN],
    ["H2 confirmée", "La crainte des litiges justifie le paiement séquestre Mobile Money + cycle de devis.", GREEN],
    ["H3 confirmée", "KYC obligatoire et interface mobile-first deviennent des leviers d'adoption.", AMBER],
  ];
  let y = 2.1;
  items.forEach((it) => {
    card(s, 1.3, y, 11.4, 1.4, WHITE);
    s.addShape(pres.shapes.RECTANGLE, { x: 1.3, y, w: 0.12, h: 1.4, fill: { color: it[2] } });
    s.addText(it[0], { x: 1.6, y: y + 0.2, w: 2.7, h: 1.0, valign: "middle", fontFace: HF, bold: true, fontSize: 18, color: NAVY });
    s.addText(it[1], { x: 4.35, y: y + 0.2, w: 8.1, h: 1.0, valign: "middle", fontFace: BF, fontSize: 14.5, color: INK, lineSpacingMultiple: 1.08 });
    y += 1.55;
  });
})();

// =================================================================
// 10 — Solution proposée
// =================================================================
(() => {
  const s = contentSlide(10, "Solution proposée : BABIFIX");
  s.addText("Une place de marché à 4 interfaces reliées à un même serveur central :", { x: 1.3, y: 1.45, w: 11, h: 0.35, fontFace: BF, fontSize: 13.5, color: INK });
  const comps = [
    ["App Client", "Recherche géoloc., réservation, devis, paiement, avis, fidélité."],
    ["App Prestataire", "Profil, KYC, devis, agenda, portefeuille, premium."],
    ["Back-office Admin", "Validation KYC, litiges, paiements, actualités."],
    ["Site vitrine", "Présentation, téléchargement, SEO, consentement RGPD."],
  ];
  const cw = 2.72, gap = 0.18;
  comps.forEach((c, i) => {
    const x = 1.3 + i * (cw + gap);
    card(s, x, 1.9, cw, 1.75, NAVY);
    s.addText(c[0], { x: x + 0.2, y: 2.08, w: cw - 0.4, h: 0.45, fontFace: HF, bold: true, fontSize: 14.5, color: CYAN });
    s.addText(c[1], { x: x + 0.2, y: 2.5, w: cw - 0.4, h: 1.05, fontFace: BF, fontSize: 11.5, color: ICE, lineSpacingMultiple: 1.03 });
  });
  // 3 piliers
  s.addText("Trois piliers de valeur", { x: 1.3, y: 3.85, w: 11, h: 0.35, fontFace: HF, bold: true, fontSize: 15, color: NAVY });
  const pil = [["Confiance", "KYC (CNI + photo) + validation admin + notation bidirectionnelle"], ["Transparence", "Cycle de devis : prix accepté avant l'intervention"], ["Sécurité", "Paiement séquestre en FCFA (Mobile Money / espèces)"]];
  pil.forEach((p, i) => {
    const x = 1.3 + i * 3.86;
    card(s, x, 4.25, 3.66, 1.15, LIGHT);
    s.addText(p[0], { x: x + 0.2, y: 4.35, w: 3.3, h: 0.4, fontFace: HF, bold: true, fontSize: 14, color: [CYAN, AMBER, GREEN][i] === CYAN ? NAVY : NAVY });
    s.addText(p[1], { x: x + 0.2, y: 4.72, w: 3.3, h: 0.6, fontFace: BF, fontSize: 11, color: INK, lineSpacingMultiple: 1.02 });
  });
  // modèle éco
  card(s, 1.3, 5.6, 11.4, 1.35, NAVY);
  s.addText("Modèle économique", { x: 1.55, y: 5.72, w: 11, h: 0.35, fontFace: HF, bold: true, fontSize: 13, color: CYAN });
  s.addText("Commission de 18 % à la finalisation  +  abonnement premium prestataire : Standard (18 %) · Silver 7 500 F (≈13 %) · Gold 15 000 F (≈8 %), visibilité et quota de devis croissants.",
    { x: 1.55, y: 6.08, w: 11, h: 0.75, fontFace: BF, fontSize: 12.5, color: ICE, lineSpacingMultiple: 1.05 });
})();

// =================================================================
// 11 — Modélisation UML
// =================================================================
(() => {
  const s = contentSlide(11, "Modélisation du système (UML)");
  s.addText("Cinq familles de diagrammes produites avec PlantUML :", { x: 1.3, y: 1.45, w: 11, h: 0.35, fontFace: BF, fontSize: 13.5, color: INK });
  const diags = [
    ["Cas d'utilisation", "Interactions acteurs ↔ système (client, prestataire, admin)"],
    ["Classes", "Structure des données : Utilisateur, Réservation, Devis, Paiement…"],
    ["Séquence", "Réservation & paiement, pas à pas"],
    ["Activité", "Inscription prestataire (accept / refus / resoumission)"],
    ["État", "Cycle de vie d'une réservation"],
  ];
  const cw = 3.66, ch = 1.3, gap = 0.2;
  diags.forEach((d, i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const x = 1.3 + col * (cw + gap);
    const y = 1.9 + row * (ch + gap);
    card(s, x, y, cw, ch, LIGHT);
    s.addShape(pres.shapes.OVAL, { x: x + 0.22, y: y + 0.22, w: 0.45, h: 0.45, fill: { color: CYAN } });
    s.addText(String(i + 1), { x: x + 0.22, y: y + 0.22, w: 0.45, h: 0.45, align: "center", valign: "middle", fontFace: HF, bold: true, fontSize: 15, color: NAVY });
    s.addText(d[0], { x: x + 0.8, y: y + 0.18, w: cw - 1.0, h: 0.4, fontFace: HF, bold: true, fontSize: 14, color: NAVY });
    s.addText(d[1], { x: x + 0.8, y: y + 0.56, w: cw - 1.0, h: 0.65, fontFace: BF, fontSize: 10.5, color: SLATE, lineSpacingMultiple: 1.0 });
  });
  // placeholder zone for an inserted figure
  card(s, 9.36, 1.9, 3.34, 2.8, WHITE);
  s.addText("[ Insérer ici une figure UML\ndu mémoire — ex. diagramme\nde classes ou de séquence ]", { x: 9.46, y: 1.9, w: 3.14, h: 2.8, align: "center", valign: "middle", fontFace: BF, italic: true, fontSize: 11.5, color: SLATE });
  s.addText("Conseil jury : insère tous tes diagrammes, mais n'en commente que 2 (ex. cas d'utilisation + séquence). Reviens sur les autres à la demande.", { x: 1.3, y: 5.0, w: 11.4, h: 0.7, fontFace: BF, italic: true, fontSize: 12, color: PURPLE, lineSpacingMultiple: 1.05 });
})();

// =================================================================
// 12 — Architecture technique
// =================================================================
(() => {
  const s = contentSlide(12, "Architecture & technologies");
  function box(x, y, w, h, t, sub, fill, tc) {
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: fill }, line: { color: LINE, width: 1 }, shadow: shadow() });
    s.addText([{ text: t, options: { bold: true, fontSize: 13.5, color: tc, breakLine: true } }, { text: sub, options: { fontSize: 10, color: tc === WHITE ? ICE : SLATE } }],
      { x: x + 0.1, y: y + 0.1, w: w - 0.2, h: h - 0.2, align: "center", valign: "middle", fontFace: BF });
  }
  box(0.9, 1.7, 3.0, 1.0, "App Client", "Flutter (Dart)", LIGHT, NAVY);
  box(0.9, 2.9, 3.0, 1.0, "App Prestataire", "Flutter (Dart)", LIGHT, NAVY);
  box(0.9, 4.1, 3.0, 1.0, "Site vitrine", "Web", LIGHT, NAVY);
  box(5.1, 2.55, 3.2, 1.95, "Serveur BABIFIX", "Django 5 · API REST\nChannels (WebSocket) · Daphne", NAVY, WHITE);
  box(9.5, 1.55, 3.2, 0.92, "PostgreSQL", "Base de données", LIGHT, NAVY);
  box(9.5, 2.62, 3.2, 0.92, "Cloudinary", "Stockage médias", LIGHT, NAVY);
  box(9.5, 3.69, 3.2, 0.92, "Firebase FCM", "Notifications push", LIGHT, NAVY);
  box(9.5, 4.76, 3.2, 0.92, "GeniusPay", "Mobile Money (4 opérateurs)", LIGHT, NAVY);
  const arrow = (x, y, w) => s.addShape(pres.shapes.LINE, { x, y, w, h: 0, line: { color: CYAN, width: 2.5, beginArrowType: "triangle", endArrowType: "triangle" } });
  arrow(3.9, 3.5, 1.2); arrow(8.3, 3.5, 1.2);
  s.addText("Architecture en 3 couches (présentation · logique métier · données). Choix guidés par la robustesse, la productivité et l'adéquation au marché ivoirien.",
    { x: 1.3, y: 6.0, w: 11.4, h: 0.8, fontFace: BF, italic: true, fontSize: 12.5, color: SLATE, align: "center", lineSpacingMultiple: 1.05 });
})();

// =================================================================
// 13 — Démonstration
// =================================================================
(() => {
  const s = pres.addSlide();
  s.background = { color: NAVY };
  s.addShape(pres.shapes.OVAL, { x: -1.6, y: 4.4, w: 4.6, h: 4.6, fill: { color: NAVY2 } });
  s.addText("DÉMONSTRATION LIVE", { x: 0.9, y: 0.95, w: 11.5, h: 0.5, fontFace: HF, bold: true, fontSize: 15, color: CYAN, charSpacing: 2 });
  s.addText("Parcours utilisateur de bout en bout", { x: 0.9, y: 1.5, w: 11.5, h: 0.85, fontFace: HF, bold: true, fontSize: 32, color: WHITE });
  const steps = [
    "Inscription, vérification & connexion",
    "Recherche géolocalisée d'un prestataire vérifié",
    "Réservation, devis & acceptation",
    "Chat temps réel lié à la réservation",
    "Paiement séquestre (Mobile Money) puis notation",
  ];
  let y = 2.75;
  steps.forEach((t, i) => {
    s.addShape(pres.shapes.OVAL, { x: 1.2, y, w: 0.65, h: 0.65, fill: { color: CYAN } });
    s.addText(String(i + 1), { x: 1.2, y, w: 0.65, h: 0.65, align: "center", valign: "middle", fontFace: HF, bold: true, fontSize: 20, color: NAVY });
    s.addText(t, { x: 2.15, y, w: 10.3, h: 0.65, valign: "middle", fontFace: BF, fontSize: 18, color: WHITE });
    y += 0.82;
  });
})();

// =================================================================
// 14 — Validation
// =================================================================
(() => {
  const s = contentSlide(14, "Tests & validation de la solution");
  const H = (t) => ({ text: t, options: { bold: true, color: WHITE, fill: { color: NAVY }, align: "left" } });
  const rows = [
    [H("Type de test"), H("Objet"), H("Résultat")],
    ["Unitaires", "Calculs : devis, commission, transitions de statut", "Conformes"],
    ["Fonctionnels", "Parcours réservation → devis → paiement → évaluation", "Validés"],
    ["Sécurité", "Authentification, contrôle d'accès, validation des entrées", "Satisfaisants"],
    ["Charge", "Comportement sous sollicitations croissantes", "Stable"],
  ];
  const data = rows.map((r) => r.map((c) => typeof c === "string" ? { text: c } : c));
  s.addTable(data, { x: 1.3, y: 1.6, w: 11.4, colW: [2.6, 6.4, 2.4], rowH: 0.62, fontFace: BF, fontSize: 13, color: INK, valign: "middle", border: { type: "solid", pt: 1, color: LINE }, fill: { color: WHITE } });
  // bilan
  s.addText("Bilan : objectifs atteints", { x: 1.3, y: 4.6, w: 11, h: 0.4, fontFace: HF, bold: true, fontSize: 16, color: NAVY });
  const ok = ["Analyse du marché & de l'existant", "Recueil & spécification des besoins", "Modélisation UML complète", "4 interfaces + serveur réalisés", "Paiement Mobile Money / espèces", "Parcours utilisateur testé"];
  s.addText(ok.map((t) => ({ text: t, options: { bullet: { code: "2713" }, color: INK, breakLine: true, paraSpaceAfter: 5 } })),
    { x: 1.4, y: 5.05, w: 11, h: 1.8, fontFace: BF, fontSize: 13.5 });
})();

// =================================================================
// 15 — Limites
// =================================================================
(() => {
  const s = contentSlide(15, "Limites de l'étude");
  const lims = [
    ["Périmètre géographique", "Enquête centrée sur Abidjan : généralisation à confirmer."],
    ["Paiement en simulation", "GeniusPay opéré en mode simulé : à valider en conditions réelles."],
    ["Amorçage « two-sided »", "Densité offre/demande à construire (pilote concentré requis)."],
    ["KYC & connectivité", "CNI parfois abîmées ; couverture internet hétérogène."],
  ];
  lims.forEach((l, i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 1.3 + col * 5.75;
    const y = 1.65 + row * 2.3;
    card(s, x, y, 5.45, 2.0, WHITE);
    s.addShape(pres.shapes.RECTANGLE, { x, y, w: 0.12, h: 2.0, fill: { color: AMBER } });
    s.addText(l[0], { x: x + 0.35, y: y + 0.25, w: 4.9, h: 0.5, fontFace: HF, bold: true, fontSize: 16, color: NAVY });
    s.addText(l[1], { x: x + 0.35, y: y + 0.8, w: 4.9, h: 1.0, fontFace: BF, fontSize: 13.5, color: INK, lineSpacingMultiple: 1.1 });
  });
})();

// =================================================================
// 16 — Conclusion & perspectives
// =================================================================
(() => {
  const s = contentSlide(16, "Conclusion & perspectives");
  s.addText("BABIFIX répond à un besoin réel par une solution fiable, géolocalisée et adaptée au contexte ivoirien — économiquement viable.", { x: 1.3, y: 1.45, w: 11.4, h: 0.8, fontFace: BF, fontSize: 15.5, color: INK, lineSpacingMultiple: 1.12 });
  s.addText("Perspectives d'évolution", { x: 1.3, y: 2.4, w: 11, h: 0.4, fontFace: HF, bold: true, fontSize: 16, color: NAVY });
  const recs = [
    ["Déploiement par phases", "Pilote Cocody/Marcory → Abidjan → villes secondaires → région FCFA."],
    ["Offre B2B « BABIFIX Pro »", "Syndics, entreprises : multi-sites, SLA, facturation groupée."],
    ["Intelligence artificielle", "Prédiction de la demande, optimisation dynamique des prix."],
    ["Accessibilité", "Mode vocal / icônes pour les utilisateurs peu alphabétisés."],
  ];
  const cw = 2.72, gap = 0.18;
  recs.forEach((r, i) => {
    const x = 1.3 + i * (cw + gap);
    card(s, x, 2.85, cw, 2.0, LIGHT);
    s.addShape(pres.shapes.OVAL, { x: x + 0.2, y: 3.05, w: 0.5, h: 0.5, fill: { color: CYAN } });
    s.addText(r[0], { x: x + 0.2, y: 3.65, w: cw - 0.4, h: 0.6, fontFace: HF, bold: true, fontSize: 13.5, color: NAVY });
    s.addText(r[1], { x: x + 0.2, y: 4.2, w: cw - 0.4, h: 0.6, fontFace: BF, fontSize: 11, color: INK, lineSpacingMultiple: 1.03 });
  });
  card(s, 1.3, 5.1, 11.4, 1.45, NAVY);
  s.addText("Viabilité économique (projection prudente)", { x: 1.55, y: 5.22, w: 11, h: 0.35, fontFace: HF, bold: true, fontSize: 13, color: CYAN });
  s.addText("~500 prestataires actifs × 8 missions/mois × 12 000 F ≈ 48 M F de transactions/mois → ~8,6 M F de commission/mois (≈ 103 M F/an). LTV/CAC > 20.",
    { x: 1.55, y: 5.6, w: 11, h: 0.85, fontFace: BF, fontSize: 12.5, color: ICE, lineSpacingMultiple: 1.05 });
})();

// =================================================================
// 17 — Remerciements / Questions
// =================================================================
(() => {
  const s = pres.addSlide();
  s.background = { color: NAVY };
  s.addShape(pres.shapes.OVAL, { x: 10.2, y: -1.9, w: 5.2, h: 5.2, fill: { color: NAVY2 } });
  s.addText("Merci de votre attention", { x: 0.9, y: 2.4, w: 11.5, h: 1.0, fontFace: HF, bold: true, fontSize: 42, color: WHITE });
  s.addShape(pres.shapes.RECTANGLE, { x: 0.95, y: 3.6, w: 1.8, h: 0.07, fill: { color: CYAN } });
  s.addText("Questions & échanges avec le jury", { x: 0.9, y: 3.85, w: 11.5, h: 0.6, fontFace: BF, fontSize: 20, color: ICE });
  s.addText("KOUAKOU EBOUHO FRANCK YVAN  ·  BABIFIX  ·  IIT — Licence Génie Logiciel  ·  2025–2026", { x: 0.9, y: 6.7, w: 11.5, h: 0.4, fontFace: BF, fontSize: 12, color: SLATE });
})();

pres.writeFile({ fileName: "BABIFIX_Soutenance.pptx" }).then((f) => console.log("OK:", f));
