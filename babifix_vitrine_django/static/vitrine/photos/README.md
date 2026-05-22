# Photos vitrine BABIFIX

Ce dossier contient les **vraies photos** affichées dans la section
« BABIFIX en vrai » du site vitrine.

## 📂 Fichiers attendus

Place les images aux noms exacts ci-dessous. Tant qu'un fichier manque,
un placeholder gradient élégant s'affiche à sa place (cf. `.gal-fallback`
dans `home.html`).

### Galerie principale (6 photos, format paysage 4:3 ou portrait 3:4)

| Fichier | Sujet | Format suggéré |
|---|---|---|
| `plombier-au-travail.jpg` | Plombier ivoirien réparant un robinet / canalisation | Portrait 800×1200 |
| `cliente-satisfaite.jpg` | Cliente africaine souriante chez elle | Paysage 1200×900 |
| `electricienne-intervention.jpg` | Électricienne en intervention domicile | Paysage 1200×900 |
| `menage-domicile.jpg` | Agent d'entretien en pleine intervention | Portrait 800×1200 |
| `poignee-main-prestation.jpg` | Poignée de main entre client et prestataire | Paysage 1200×900 |
| `jardinier-abidjan.jpg` | Jardinier travaillant un espace vert | Paysage 1200×900 |

### Avatars témoignages (3 photos, format carré)

| Fichier | Sujet | Format |
|---|---|---|
| `avatars/avatar-mariam.jpg` | Cliente Mariam D. | Carré 200×200 |
| `avatars/avatar-yao.jpg` | Plombier Yao K. | Carré 200×200 |
| `avatars/avatar-aminata.jpg` | Cliente Aminata B. | Carré 200×200 |

## 📷 Sources libres de droits recommandées

Toutes ces banques offrent des photos gratuites, libres d'usage
commercial, sans attribution requise :

- **Pexels** — https://www.pexels.com/search/
- **Unsplash** — https://unsplash.com/s/photos/
- **Pixabay** — https://pixabay.com/

### Mots-clés à utiliser (contexte ivoirien / africain)

- Plombier → `african plumber`, `black plumber working`
- Électricienne → `black female electrician`, `african electrician`
- Ménage → `african cleaning service`, `housekeeper black`
- Cliente satisfaite → `african woman smiling home`, `ivorian woman`
- Jardinier → `african gardener`, `west african gardener`
- Poignée de main → `handshake african`, `black handshake business`
- Avatars → `african portrait`, `ivorian portrait professional`

## ⚙️ Optimisation (avant upload)

Pour de bonnes perfs :

```bash
# Compresser en jpeg qualité 80, max 1200px de large
# (Linux/Mac avec ImageMagick installé)
for f in *.jpg; do
  convert "$f" -resize 1200x\> -quality 80 "$f"
done

# Ou en ligne : https://squoosh.app/
```

Cibles : **< 200 ko par image principale**, **< 30 ko par avatar**.

## 🎨 Si tu veux générer des fallbacks SVG en attendant

Les balises `<img>` ont déjà un `onerror` qui transforme le conteneur en
gradient cyan/navy/orange BABIFIX → **aucun rendu cassé** si tu mets en
prod sans les photos. Mais évidemment c'est moins humain.

## ✅ Une fois les photos en place

- `flutter` n'est pas concerné (c'est uniquement le site vitrine)
- `collectstatic` ramassera les fichiers en prod
- Le caching Django + `loading="lazy"` font le reste
