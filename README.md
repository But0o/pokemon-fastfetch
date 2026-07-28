# ⚡ Pokémon Fastfetch

Display a random Pokémon every time you open your terminal.

Pokémon Fastfetch combines **Fastfetch**, **Kitty graphics**, and a **locally cached Pokédex** to create a fast and visually appealing terminal startup.

![Preview](docs/preview.png)

---

# ✨ Features

- 🎲 Random Pokémon on every terminal launch
- ⚡ Extremely fast startup
- 💾 Offline Pokédex cache
- 🖼️ Kitty image support
- 🐟 Fish shell integration
- 🔄 Upgrade script
- 🗑️ Uninstaller
- 🛠️ Automatic installer

---

# 📦 Requirements

- Linux
- Kitty Terminal
- Fish (recommended)
- Fastfetch
- jq
- ImageMagick
- pokimg

Arch/CachyOS:

```bash
sudo pacman -S fastfetch kitty jq imagemagick fish
```

---

# 🚀 Installation

Clone the repository:

```bash
git clone https://github.com/But0o/pokemon-fastfetch.git
cd pokemon-fastfetch
```

Give execution permissions:

```bash
chmod +x install.sh
```

Run the installer:

```bash
./install.sh
```

The installer automatically:

- Detects pokimg
- Creates the required directories
- Configures Fish
- Installs Pokémon Fastfetch
- Preserves future upgrades

---

# 🔄 Upgrade

```bash
chmod +x upgrade-v1-to-v2.sh
./upgrade-v1-to-v2.sh
```

---

# 🗑️ Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

Remove cache and backups:

```bash
./uninstall.sh --remove-cache --remove-backups
```

---

# 📁 Project structure

```text
pokemon-fastfetch/
├── build-pokedex-cache.sh
├── random-fastfetch.sh
├── render-pokemon.sh
├── install.sh
├── upgrade-v1-to-v2.sh
├── uninstall.sh
├── README.md
├── LICENSE
├── CHANGELOG.md
├── VERSION
├── docs/
├── config/
└── fish/
```

---

# ⚙️ Configuration

Configuration is stored in:

```text
~/.config/pokemon-fastfetch/config
```

Cache:

```text
~/.cache/pokemon-fastfetch
```

Installation:

```text
~/.local/share/pokemon-fastfetch
```

---

# 🧪 Tested on

- ✅ CachyOS
- ✅ Arch Linux
- ✅ Fish Shell
- ✅ Kitty Terminal

---

# 📄 License

This project is distributed under the MIT License.

See the **LICENSE** file for details.