# Tailwind CSS 3 (optionnel) — panel admin

Le panel utilise aujourd’hui **`static/adminpanel/style.css`** (CSS custom) + HTMX + Chart.js. Ce dossier permet d’ajouter un **build Tailwind** si vous souhaitez des utilitaires `tw-*` sans tout réécrire.

## Installation

```bash
cd static_src/tailwind
npm install
npm run build
```

Le fichier généré peut être inclus dans les templates après `style.css` :

```html
<link rel="stylesheet" href="{% static 'adminpanel/tw-build.css' %}">
```

Configurer `tailwind.config.js` avec `prefix: 'tw-'` pour éviter les collisions avec les classes existantes.

## Fichiers à créer localement

- `package.json` (tailwindcss 3.x, postcss, autoprefixer)
- `tailwind.config.js` (`content: ['../../templates/**/*.html']`)
- `input.css` (`@tailwind base; @tailwind components; @tailwind utilities;`)

Les fichiers ne sont pas imposés dans le dépôt pour ne pas imposer Node.js à tous les contributeurs.
