# SMPWORK · MinimaHub

**Hub compact pour Roblox / Xeno executor — par Akram Abbaoui & Amjad Nejjari.**

Version **1.3.0** · Lua propre, non obfusqué, sans anti-debug ni vérification d'environnement.

---

## ⚡ Démarrage rapide (2 minutes)

### 1. Mettre les fichiers sur GitHub

Crée un dépôt public nommé **`Fortoo`**, puis uploade **à la racine** :

```
SMPWORK.lua
loader.lua
README.md
LICENSE
.gitignore
```

> Le nom du dépôt (`Fortoo`) et la branche (`main`) sont déjà réglés dans
> `loader.lua`. Si tu utilises un autre nom de dépôt, change aussi `GITHUB_REPO`.
>
> Tu peux aussi glisser le **dossier `Fortoo` entier** dans GitHub : le loader
> essaie automatiquement les deux emplacements (`/SMPWORK.lua` et
> `/Fortoo/SMPWORK.lua`).

### 2. Mettre ton pseudo GitHub (1 seule ligne)

Ouvre `loader.lua`, ligne **24** :

```lua
local GITHUB_USER   = "YOUR_USER"   --  <-- mets ton pseudo GitHub ici
```

Exemple : `local GITHUB_USER = "AkramX"`.

### 3. Lancer dans Xeno

1. Ouvre Roblox, puis Xeno.
2. Onglet script → colle **tout** le contenu de `loader.lua`.
3. **Execute**.
4. Appuie sur **RightControl** pour afficher / cacher le menu.

Le loader télécharge `SMPWORK.lua` depuis GitHub, prévient le hub de l'URL
utilisée (`getgenv().SMPWORK_URL`), puis le lance. Résultat : *Auto reattach*,
*Check for updates* et *Reload from GitHub* fonctionnent **sans rien éditer**
dans `SMPWORK.lua`.

### Sans GitHub

Tu peux aussi coller directement **tout** `SMPWORK.lua` dans Xeno. Tout marche
de la même façon, sauf les boutons qui ont besoin de l'URL (`Auto reattach`,
`Check for updates`, `Reload from GitHub`) — pour ceux-là, remplace `YOUR_USER`
ligne **32** de `SMPWORK.lua`.

---

## 📁 Fichiers

| Fichier | Rôle |
| --- | --- |
| `SMPWORK.lua` | Le hub complet (interface + toutes les features). |
| `loader.lua` | Le lanceur GitHub : télécharge et exécute `SMPWORK.lua`. |
| `README.md` | Ce fichier. |
| `LICENSE` | MIT — conserve le crédit des auteurs. |
| `.gitignore` | Empêche de publier la config locale (`SMPWORK.json`). |

---

## ✨ Fonctionnalités

### ESP
- Box, Glow (Highlight), Skeleton (R6 + R15), Nametag (pseudo / vie / distance), Tracers.
- **Fonctionne même si `Drawing.new("Square")` n'existe pas** : la box bascule
  automatiquement sur 4 lignes.
- Chaque joueur est isolé (`pcall`) : une erreur sur un perso ne coupe pas l'ESP
  des autres.
- Wall check (recolore la cible derrière un mur) — désactivé = zéro coût rayon.
- Couleurs séparées : visible / caché / squelette / tracers.

### Aimbot
- **Aim without RMB** : verrouille sans maintenir le clic droit.
- Cible : `Head`, `UpperTorso`, `HumanoidRootPart`.
- FOV (rayon en pixels), portée max (studs), lissage, wall check.
- Caméra liée à `RenderPriority.Camera + 1` (avec repli `RenderStepped`) : verrou
  rapide et stable, sans tremblement.
- Anneau de FOV affiché autour du curseur.

### Mouvement
- Walk speed / Jump power.
- **Fly** (touche `E`) : W/A/S/D, `Espace` = monter, `Ctrl gauche` = descendre.
- Noclip, Infinite jump, Safewalk.
- Safewalk et Spinbot se mettent en pause pendant le fly (pas de conflit), et le
  `PlatformStand` est restauré à l'arrêt du fly.

### Combat
- Hitbox expander (taille réglable), Spinbot (vitesse réglable), FOV custom.

### Utils / Config
- Click teleport, Server hopper, Auto reattach (survit aux téléports),
  lancement de Dex / Infinite Yield / autres.
- Save / Load / Reset config (fichier `SMPWORK.json`).
- Check for updates, Reload from GitHub.
- **Mode bulle** : voir plus bas.

---

## 🫧 Mode bulle (photo d'équipe)

Deux façons de passer en bulle :

1. Clique sur le **bouton rond** à gauche des boutons `-` / `x` de la barre de titre.
2. Menu **Config → Interface → Bubble mode**.

Le menu se replie en une **bulle ronde de 58 px** avec la photo, une pastille
verte quand une feature est active, et une infobulle au survol. Clique sur la
bulle pour rouvrir le menu. La bulle se déplace en la faisant glisser.

### Changer la photo

Dans `SMPWORK.lua`, ligne **48** :

```lua
local TEAM_PHOTO = ""   -- ex: "rbxassetid://1234567890"
```

- Vide `""` → affiche l'avatar Roblox du joueur local (`rbxthumb://`).
- Sinon : un `rbxassetid://...` (image importée) ou `rbxthumb://...`.

---

## ⌨️ Raccourcis

| Touche | Action |
| --- | --- |
| `RightControl` | Afficher / cacher le menu (et la bulle). |
| `Clic droit` | Viser (si *Aim without RMB* est désactivé). |
| `E` | Activer / désactiver le Fly. |
| `W A S D` | Se déplacer en Fly. |
| `Espace` / `Ctrl gauche` | Monter / descendre en Fly. |
| `Clic gauche` | Téléportation au curseur (si *Click teleport* est activé). |

---

## 🧪 Vérifications

La suite de tests du projet passe intégralement :

```
syntax     OK   SMPWORK.lua (2793 lignes, 152 statements) · loader.lua (183 lignes)
hub        48 passed
fly        25 passed
aim/move   18 passed
esp        37 passed   (toutes features ON, fallback Square, bulle aller-retour)
loader     12 passed
reload      8 passed
update      6 + 6 passed
layout      0 problème
ALL CHECKS PASSED
```

---

## 🛠️ Dépannage

| Message / problème | Solution |
| --- | --- |
| `SOURCES is not configured yet` | Remplace `YOUR_USER` ligne 24 de `loader.lua`. |
| `could not download the script` | Dépôt **public**, fichier **à la racine**, branche **`main`**. |
| `the downloaded file does not look like SMPWORK.lua` | Le chemin renvoie une page 404 : vérifie le nom du fichier. |
| Rien ne s'affiche | Ton executor doit fournir l'API `Drawing`. |
| ESP sans box | Normal si `Drawing.new("Square")` manque : les 4 lignes prennent le relais. |
| `Update check failed: SELF_URL is not configured yet` | Lance via `loader.lua`, ou édite la ligne 32 de `SMPWORK.lua`. |
| La config ne se sauvegarde pas | `writefile` / `readfile` absents de l'executor. |

---

## ⚠️ Avertissement

Projet **éducatif / de test**. Modifier le client Roblox viole les Conditions
d'utilisation de Roblox et peut entraîner un bannissement. Utilise-le sur un
compte de test, à tes risques.

---

**by Akram Abbaoui & Amjad Nejjari** · SMPWORK v1.3.0
