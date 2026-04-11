# BABIFIX — Backend Django avec WAMP (MySQL, `root` sans mot de passe)

## Automatisation (recommandé)

Depuis le dossier `BABIFIX_BUILD` :

```powershell
.\scripts\bootstrap_babifix_admin.ps1
```

Ce script : crée le venv si besoin, `pip install -r requirements.txt`, **recrée** la base MySQL `babifix` (DROP + CREATE — **efface les données**), `migrate`, et crée le superutilisateur `babifix_admin` / `BabifixDev2026!` s’il n’existe pas.

## 1. Erreur `No module named 'daphne'`

Le venv doit contenir **toutes** les dépendances du fichier `requirements.txt` :

```powershell
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_admin_django
.\.venv\Scripts\activate
pip install -U pip
pip install -r requirements.txt
```

Sans cela, `runserver` et `migrate` échouent car `daphne` est requis dans `INSTALLED_APPS`.

## 2. Créer la base MySQL (phpMyAdmin)

1. Ouvrez **http://localhost/phpmyadmin**
2. **Nouvelle base de données** : nom par ex. `babifix`
3. Interclassement : **utf8mb4_unicode_ci**

## 3. Fichier `.env` dans `babifix_admin_django/`

Copiez `.env.example` vers `.env` et ajoutez (exemple WAMP classique) :

```env
MYSQL_DATABASE=babifix
MYSQL_USER=root
MYSQL_PASSWORD=
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
```

Mot de passe vide : laissez `MYSQL_PASSWORD=` vide ou supprimez la ligne (le code utilise `''` par défaut).

## 4. Migrations et serveur

```powershell
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver 0.0.0.0:8002
```

Ouvrez **`http://127.0.0.1:8002/`** (pas `0.0.0.0` dans le navigateur).

## 5. Apps Flutter (client / prestataire)

Les apps pointent par défaut vers `http://127.0.0.1:8002`. Tant que le serveur Django ne tourne pas ou que la base n’est pas migrée, vous verrez :

- *Session locale sans serveur* (messagerie sans JWT)
- *Impossible d’enregistrer le dossier* (API injoignable ou erreur serveur)

Après `pip install`, MySQL + `migrate` + `runserver`, reconnectez-vous (email + mot de passe) pour obtenir un jeton.

## Priorité des bases dans `settings.py`

1. Si `POSTGRES_DB` est défini → PostgreSQL  
2. Sinon si `MYSQL_DATABASE` est défini → MySQL (WAMP)  
3. Sinon → SQLite (`db.sqlite3`)

## 6. Erreur MySQL « La clé est trop longue » (`DeviceToken`)

L’index UNIQUE sur le jeton FCM est limité à **191** caractères (utf8mb4 / InnoDB). Si une migration a échoué au milieu, supprimez la base `babifix` et relancez `migrate`, ou exécutez `.\scripts\bootstrap_babifix_admin.ps1` (réinitialise la base).
