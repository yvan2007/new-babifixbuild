// Génération CV professionnel KOUAKOU EBOUHO FRANCK YVAN
const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat,
  TabStopType, BorderStyle, WidthType,
  ShadingType, VerticalAlign, PageNumber,
} = require("docx");

// ─── Palette ─────────────────────────────────────────────
const NAVY  = "0F172A";
const CYAN  = "06B6D4";
const SUB   = "475569";
const LIGHT = "F1F5F9";
const BORDER_GREY = "CBD5E1";

const border = { style: BorderStyle.SINGLE, size: 4, color: BORDER_GREY };
const borders = { top: border, bottom: border, left: border, right: border };
const noBorder = { style: BorderStyle.NONE, size: 0, color: "FFFFFF" };
const noBorders = { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder };

// ─── Helpers ─────────────────────────────────────────────────────
const p = (text, opts = {}) =>
  new Paragraph({
    spacing: { after: 100, ...(opts.spacing || {}) },
    alignment: opts.alignment,
    indent: opts.indent,
    children: [
      new TextRun({
        text,
        font: "Arial",
        size: opts.size || 20,
        bold: opts.bold,
        italics: opts.italics,
        color: opts.color || "1F2937",
      }),
    ],
  });

const bullet = (text, opts = {}) =>
  new Paragraph({
    numbering: { reference: "bullets", level: 0 },
    spacing: { after: 60 },
    children: [
      new TextRun({
        text,
        font: "Arial",
        size: 20,
        color: "1F2937",
        bold: opts.bold,
      }),
    ],
  });

const sectionTitle = (text) =>
  new Paragraph({
    spacing: { before: 320, after: 160 },
    border: {
      bottom: { style: BorderStyle.SINGLE, size: 8, color: CYAN, space: 4 },
    },
    children: [
      new TextRun({
        text: text.toUpperCase(),
        font: "Arial",
        size: 24,
        bold: true,
        color: NAVY,
      }),
    ],
  });

const jobHeader = (title, company, dates) =>
  new Paragraph({
    spacing: { before: 200, after: 80 },
    tabStops: [{ type: TabStopType.RIGHT, position: 9200 }],
    children: [
      new TextRun({ text: title, font: "Arial", size: 22, bold: true, color: NAVY }),
      new TextRun({ text: "  |  ", font: "Arial", size: 22, color: SUB }),
      new TextRun({ text: company, font: "Arial", size: 22, italics: true, color: CYAN, bold: true }),
      new TextRun({ text: "\t", font: "Arial" }),
      new TextRun({ text: dates, font: "Arial", size: 20, italics: true, color: SUB }),
    ],
  });

const skillCellLabel = (text, width) =>
  new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: NAVY, type: ShadingType.CLEAR, color: "auto" },
    margins: { top: 100, bottom: 100, left: 150, right: 100 },
    verticalAlign: VerticalAlign.CENTER,
    children: [
      new Paragraph({
        spacing: { after: 0 },
        children: [
          new TextRun({ text, font: "Arial", size: 20, bold: true, color: "FFFFFF" }),
        ],
      }),
    ],
  });

const skillCellValue = (text, width) =>
  new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: LIGHT, type: ShadingType.CLEAR, color: "auto" },
    margins: { top: 100, bottom: 100, left: 150, right: 100 },
    verticalAlign: VerticalAlign.CENTER,
    children: [
      new Paragraph({
        spacing: { after: 0 },
        children: [new TextRun({ text, font: "Arial", size: 20, color: "1F2937" })],
      }),
    ],
  });

const skillRow = (label, value) =>
  new TableRow({
    children: [skillCellLabel(label, 2700), skillCellValue(value, 6500)],
  });

// ─── EN-TÊTE ────────────────────────────────────────
const headerName = new Paragraph({
  spacing: { after: 80 },
  alignment: AlignmentType.CENTER,
  children: [
    new TextRun({
      text: "KOUAKOU EBOUHO FRANCK YVAN",
      font: "Arial",
      size: 48,
      bold: true,
      color: NAVY,
    }),
  ],
});

const headerSub = new Paragraph({
  spacing: { after: 120 },
  alignment: AlignmentType.CENTER,
  children: [
    new TextRun({
      text: "Informaticien – Ingénieur en Logiciel",
      font: "Arial",
      size: 22,
      color: CYAN,
      bold: true,
    }),
  ],
});

const headerContact = new Paragraph({
  spacing: { after: 80 },
  alignment: AlignmentType.CENTER,
  children: [
    new TextRun({
      text: "0160398864  •  kouayavana20@gmail.com  •  Permis AB",
      font: "Arial",
      size: 19,
      color: SUB,
    }),
  ],
});

const headerLinks = new Paragraph({
  spacing: { after: 200 },
  alignment: AlignmentType.CENTER,
  children: [
    new TextRun({
      text: "Portfolio",
      font: "Arial",
      size: 19,
      color: SUB,
      italics: true,
    }),
    new TextRun({
      text: " : https://portfolio-ebon-two-26.vercel.app/",
      font: "Arial",
      size: 19,
      color: CYAN,
      italics: true,
    }),
  ],
});

const headerSeparator = new Paragraph({
  spacing: { after: 0 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: NAVY, space: 6 } },
  children: [new TextRun({ text: "", font: "Arial" })],
});

// ─── PROFIL ──────────────────────────────────────────
const profile = p(
  "Étudiant en Licence Informatique, passionné par le développement logiciel et les nouvelles " +
    "technologies. Doté d'une forte capacité d'apprentissage et d'un esprit créatif, je conçois " +
    "des applications web et mobiles répondant aux besoins concrets du marché. Rigoureux et " +
    "persévérant, je sais travailler en équipe et m'adapter rapidement à de nouveaux environnements techniques.",
  { spacing: { after: 100 } }
);

// ─── PROJETS ACADÉMIQUES ET PERSONNELS ────────────────
const xpProjects = [
  new Paragraph({
    spacing: { before: 100, after: 80 },
    children: [
      new TextRun({
        text: "Développement Web et d'Applications",
        font: "Arial",
        size: 20,
        bold: true,
        color: NAVY,
      }),
    ],
  }),
  bullet(
    "Site de shopping style Jumia (Django/Python) : E-commerce complet avec gestion de produits, panier, paiements et authentification utilisateur."
  ),
  bullet(
    "Application de réservation de compétitions (Flask/Python) : Gestion des inscriptions, calendrier, notifications et suivi des utilisateurs."
  ),
  bullet(
    "Application mobile Flutter – projet académique : Application de gestion personnelle avec authentification sécurisée et stockage local JSON."
  ),
  bullet(
    "Application mobile Flutter – projet personnel : Application de gestion des tâches et notes personnelles présentée devant l'école."
  ),
  bullet(
    "Interface de gestion scolaire (PHP/MySQL) : Tableau de bord administrateur – suivi des inscriptions, paiements, notes et notifications."
  ),
  new Paragraph({
    spacing: { before: 120, after: 80 },
    children: [
      new TextRun({
        text: "Flotte Automobile",
        font: "Arial",
        size: 20,
        bold: true,
        color: NAVY,
      }),
    ],
  }),
  bullet(
    "Optimisation d'une flotte de véhicules pour répondre aux besoins d'une entreprise (livraison, transport, maintenance)."
  ),
  new Paragraph({
    spacing: { before: 120, after: 80 },
    children: [
      new TextRun({
        text: "Données & Analyse",
        font: "Arial",
        size: 20,
        bold: true,
        color: NAVY,
      }),
    ],
  }),
  bullet(
    "Application d'Intelligence d'Affaires (Python/MySQL) : Analyse de données et création de tableaux de bord pour la décision académique."
  ),
  bullet(
    "Web scraping (Python) : Extraction automatique de données de sites web pour analyses statistiques et rapports."
  ),
  new Paragraph({
    spacing: { before: 120, after: 80 },
    children: [
      new TextRun({
        text: "Robotique & IoT",
        font: "Arial",
        size: 20,
        bold: true,
        color: NAVY,
      }),
    ],
  }),
  bullet(
    "Détecteur de mouvement, capteur de température et autres dispositifs pour applications pratiques."
  ),
];

// ─── COMPÉTENCES TECHNIQUES ──────────────────────────
const skillsTable = new Table({
  width: { size: 9200, type: WidthType.DXA },
  columnWidths: [2700, 6500],
  rows: [
    skillRow("Python / Django / Flask", "Python, Django, Flask, Web Scraping, API REST"),
    skillRow("Mobile (Flutter / Dart)", "Flutter, Dart, Dart/Flutter"),
    skillRow("PHP / Laravel", "PHP, Laravel, MySQL"),
    skillRow("C# / .NET", "C#, ASP.NET Core, MVC, Entity Framework"),
    skillRow("Java", "Java"),
    skillRow("Frontend", "HTML5, CSS3, JavaScript"),
    skillRow("ERP", "Odoo"),
    skillRow("Bases de données", "MySQL, SQLite"),
    skillRow("Outils", "WampServer, VS Code, Visual Studio, Git, GitHub, Canva, Word, PowerPoint, Photoshop"),
    skillRow("Robotique & IoT", "Programmation de robots, capteurs, capteurs environnementaux"),
  ],
});

// ─── FORMATION ───────────────────────────────────────
const formation = [
  jobHeader("Licence 3 Informatique (En cours)", "Institut Ivoirien de Technologie", "2025 – 2026"),
  p("Grand-Bassam", { italics: true, color: SUB, size: 19, spacing: { after: 80 } }),
  jobHeader("Licence 2 Informatique", "Institut Ivoirien de Technologie", "2024 – 2025"),
  p("Grand-Bassam", { italics: true, color: SUB, size: 19, spacing: { after: 80 } }),
  jobHeader("Licence 1 Informatique", "Institut Ivoirien de Technologie", "2023 – 2024"),
  p("Grand-Bassam", { italics: true, color: SUB, size: 19, spacing: { after: 80 } }),
  jobHeader("Baccalauréat D", "Collège Robert-Leon", "2022 – 2023"),
  p("Grand-Bassam", { italics: true, color: SUB, size: 19, spacing: { after: 80 } }),
];

// ─── LANGUES ─────────────────────────────────────────
const langTable = new Table({
  width: { size: 9200, type: WidthType.DXA },
  columnWidths: [2700, 6500],
  rows: [
    skillRow("Français", "Avancé"),
    skillRow("Anglais", "Intermédiaire"),
    skillRow("Espagnol", "Intermédiaire"),
  ],
});

// ─── CENTRES D'INTÉRÊT ──────────────────────────────
const interests = [
  bullet("Travail d'équipe sur des projets techniques"),
  bullet("Football : pratique régulière, esprit d'équipe et persévérance"),
  bullet("Lecture d'articles technologiques et participation à des activités informatiques"),
];

// ─── PERSONNALITÉ ────────────────────────────────────
const personality = [
  bullet("Créatif, curieux et persévérant"),
  bullet("Joueur d'équipe avec initiative"),
];

// ─── ASSEMBLAGE DU DOCUMENT ──────────────────────────
const doc = new Document({
  creator: "KOUAKOU EBOUHO FRANCK YVAN",
  title: "CV — KOUAKOU EBOUHO FRANCK YVAN",
  description: "CV étudiant — Licence Informatique, projets académiques et personnels",
  styles: {
    default: { document: { run: { font: "Arial", size: 20 } } },
  },
  numbering: {
    config: [
      {
        reference: "bullets",
        levels: [
          {
            level: 0,
            format: LevelFormat.BULLET,
            text: "•",
            alignment: AlignmentType.LEFT,
            style: {
              paragraph: { indent: { left: 360, hanging: 220 } },
              run: { font: "Arial", color: CYAN, bold: true },
            },
          },
        ],
      },
    ],
  },
  sections: [
    {
      properties: {
        page: {
          size: { width: 11906, height: 16838 },
          margin: { top: 1000, right: 1100, bottom: 1000, left: 1100 },
        },
      },
      footers: {
        default: new Footer({
          children: [
            new Paragraph({
              alignment: AlignmentType.CENTER,
              children: [
                new TextRun({ text: "KOUAKOU EBOUHO FRANCK YVAN  •  CV  •  ", font: "Arial", size: 16, color: SUB }),
                new TextRun({ children: ["Page ", PageNumber.CURRENT], font: "Arial", size: 16, color: SUB }),
                new TextRun({ text: " / ", font: "Arial", size: 16, color: SUB }),
                new TextRun({ children: [PageNumber.TOTAL_PAGES], font: "Arial", size: 16, color: SUB }),
              ],
            }),
          ],
        }),
      },
      children: [
        headerName,
        headerSub,
        headerContact,
        headerLinks,
        headerSeparator,

        sectionTitle("Profil"),
        profile,

        sectionTitle("Projets académiques et personnels"),
        ...xpProjects,

        sectionTitle("Compétences"),
        skillsTable,

        sectionTitle("Formation"),
        ...formation,

        sectionTitle("Langues"),
        langTable,

        sectionTitle("Centres d'intérêt"),
        ...interests,

        sectionTitle("Personnalité"),
        ...personality,
      ],
    },
  ],
});

Packer.toBuffer(doc).then((buffer) => {
  const out = "C:\\Users\\kouay\\Documents\\BABIFIX_BUILD\\CV_Yvan_KOUAY.docx";
  fs.writeFileSync(out, buffer);
  console.log("OK CV genere :", out);
  console.log("  Taille :", (buffer.length / 1024).toFixed(1), "Ko");
});
