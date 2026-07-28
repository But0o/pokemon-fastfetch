# Pokémon Fastfetch

Pokédex aleatoria para Fastfetch con sprites de Pokémon, colores por tipo y caché local en formato JSON.

Cada vez que se ejecuta el script, selecciona un Pokémon aleatorio y lo muestra junto a la información del sistema.

## Características

- Pokémon aleatorio.
- Pokédex visual en estilo ASCII.
- Colores según el tipo principal.
- Número de Pokédex.
- Nombre.
- Tipo.
- Región.
- Generación.
- Categoría Normal, Legendario o Mítico.
- Caché local JSON.
- Sin consultas a Internet después de crear la caché.
- Compatible con Kitty y Fastfetch.

## Requisitos

- Linux
- Bash
- Kitty
- Fastfetch
- ImageMagick
- jq
- curl
- Git
- JetBrains Mono Nerd Font
- Imágenes de pokimg

En Arch Linux, CachyOS y derivados:

```bash
sudo pacman -S git fastfetch imagemagick jq curl findutils gawk
```

## Instalación de JetBrains Mono Nerd Font

En Arch Linux y derivados:

```bash
sudo pacman -S ttf-jetbrains-mono-nerd
```

## Instalar pokimg

Este proyecto utiliza las imágenes de:

```text
https://github.com/FuzzyGrim/pokimg
```

Las imágenes deben quedar en:

```text
~/.local/share/pokimg/images
```

## Instalar Pokémon Fastfetch

Cloná el repositorio:

```bash
git clone https://github.com/But0o/pokemon-fastfetch.git
cd pokemon-fastfetch
```

Dale permisos a los scripts:

```bash
chmod +x build-pokedex-cache.sh random-fastfetch.sh
```

Generá la caché:

```bash
./build-pokedex-cache.sh
```

La caché se guarda en:

```text
~/.cache/pokemon-fastfetch/pokedex.json
```

Probá el resultado:

```bash
./random-fastfetch.sh
```

## Utilizar otra carpeta de imágenes

Podés indicar otra ubicación:

```bash
POKEMON_DIR="/ruta/a/images" ./build-pokedex-cache.sh
```

Y después:

```bash
POKEMON_DIR="/ruta/a/images" ./random-fastfetch.sh
```

## Ejecutarlo automáticamente en Fish

Abrí:

```bash
nano ~/.config/fish/config.fish
```

Agregá:

```fish
if status is-interactive
    ~/pokemon-fastfetch/random-fastfetch.sh
end
```

Para reemplazar el comando normal `fastfetch`:

```fish
function fastfetch
    ~/pokemon-fastfetch/random-fastfetch.sh
end
```

El script utiliza internamente:

```text
/usr/bin/fastfetch
```

por lo que la función no genera una llamada recursiva.

## Actualizar la caché

Volvé a ejecutar:

```bash
./build-pokedex-cache.sh
```

Los Pokémon ya guardados se omiten automáticamente.

Para regenerarla completamente:

```bash
rm -f ~/.cache/pokemon-fastfetch/pokedex.json
./build-pokedex-cache.sh
```

## Estructura

```text
pokemon-fastfetch/
├── build-pokedex-cache.sh
├── random-fastfetch.sh
├── README.md
├── LICENSE
└── .gitignore
```

## Licencia

Este proyecto utiliza la licencia MIT.

Pokémon y sus marcas relacionadas pertenecen a sus respectivos propietarios. Este proyecto no está afiliado con Nintendo, Game Freak, Creatures Inc. ni The Pokémon Company.
