# Suel

Un visor web y mesa de juego en tiempo real para módulos de
[VASSAL](https://vassalengine.org/) (ficheros `.vmod`). Sube un módulo y juega
en el navegador —sin Java, sin cliente de escritorio—, con mapas, tableros,
rejillas hexagonales o cuadradas, fichas, mazos, dados y chat compartidos en
vivo entre jugadores.

*([README in English](README.md))*

## Qué hace

VASSAL es un motor en Java para jugar a juegos de mesa por internet. Sus módulos
(`.vmod`, que no son más que archivos ZIP) empaquetan las imágenes de los
tableros, los gráficos de las fichas, los metadatos de las reglas y los
escenarios de cada juego. **Suel** lee esos módulos directamente
—reimplementando en Ruby puro las partes necesarias del formato de fichero de
VASSAL— y los sirve como una mesa de juego web interactiva.

- **Biblioteca de módulos** — explora los módulos subidos, sus mapas y tableros,
  la paleta de fichas y los escenarios incluidos.
- **Visor de módulos** — desplaza y haz zoom sobre los mapas (renderizados con
  transformaciones CSS), con la rejilla hexagonal o cuadrada dibujada como una
  capa SVG.
- **Mesa de juego en vivo** — inicia una partida a partir de un escenario; las
  fichas colocadas del escenario se copian a un tablero editable que tú y el
  resto de jugadores manipuláis juntos vía Action Cable. Mueve, voltea, gira y
  reordena fichas en capas; roba, baraja y rehace mazos; juega cartas desde una
  mano privada; tira los dados definidos en el módulo; y chatea. Cada acción se
  retransmite en vivo a todos los de la mesa.

### Cómo funciona por dentro

Lo interesante vive en `lib/vassal/`, un port en Ruby sin dependencias de las
partes relevantes del fuente Java de VASSAL:

- `module_archive.rb` / `build_file/` lee el ZIP `.vmod` y parsea su `buildFile`
  (el árbol de definición del módulo).
- `sequence_encoder.rb` es un port exacto del `SequenceEncoder` de VASSAL, que
  decodifica las densas cadenas TYPE/STATE de las fichas. Los rasgos (traits) de
  una ficha son una codificación *recursiva* (pares de decoradores), no una
  lista plana: se pelan nivel a nivel.
- `piece/` expande los prototipos y aplica los rasgos para construir las fichas
  concretas.
- `save_file.rb` / `obfuscation.rb` lee partidas guardadas `.vsav`, incluida la
  ofuscación XOR `!VCSK` de VASSAL.
- `images.rb` obtiene los metadatos de las imágenes. Las imágenes del módulo se
  extraen a un directorio plano en disco (`storage/vassal/modules/<id>/`) y las
  sirve `ModuleAssetsController` con caché inmutable; **no** se guardan como
  blobs de Active Storage por imagen.

Subir un módulo encola `ModuleImportJob`, que extrae el archivo, parsea el árbol
de construcción y los escenarios a la base de datos, y pone el estado del módulo
en `ready`.

## Tecnología

- **Ruby 3.3** + **Rails 8.1**
- **SQLite** (mediante los adaptadores `solid_*` para caché, cola y cable: sin
  Redis ni servicios aparte)
- **Hotwire** (Turbo + Stimulus) sobre import maps, pipeline de assets
  **Propshaft**
- **Puma**, con **Solid Queue** ejecutando los jobs en segundo plano y **Solid
  Cable** moviendo la mesa en tiempo real
- `rubyzip` para leer los módulos; `ruby-vips` (cargado de forma perezosa) para
  los metadatos de las imágenes

## Requisitos

- Ruby 3.3.7 (ver `.ruby-version`)
- `libvips` en el sistema para los metadatos de las imágenes. `ruby-vips` se
  carga de forma perezosa (`require: false`), así que la app arranca sin él,
  pero la importación de módulos funciona mejor si está instalado:
  - Debian/Ubuntu: `sudo apt install libvips`
  - macOS: `brew install vips`

## Instalación

```bash
git clone <url-del-repo> suel
cd suel

# Instala las gemas y prepara la base de datos de una vez
bin/setup

# Crea el usuario administrador por defecto (admin@example.com / password)
bin/rails db:seed
```

`bin/setup` instala las dependencias, prepara la base de datos SQLite y (por
defecto) arranca el servidor de desarrollo. Para prepararlo todo sin arrancar el
servidor, usa `bin/setup --skip-server`.

### Ejecución

```bash
bin/dev
```

Esto arranca Puma y los workers en segundo plano. Abre <http://localhost:3000>.

1. Entra como el administrador sembrado (`admin@example.com` / `password`).
2. Sube un módulo `.vmod` desde la sección de administración; espera a que
   termine la importación (estado → *ready*).
3. Explora el módulo, o inicia una partida desde uno de sus escenarios e invita
   a otros a la mesa.

Cambia las credenciales del administrador sembrado con las variables de entorno
`ADMIN_EMAIL` y `ADMIN_PASSWORD`.

### Tests

```bash
bin/rails test            # tests unitarios y de integración
bin/rails test:system     # tests de sistema (Capybara + Selenium)
```

### Estilo y seguridad

```bash
bin/rubocop               # estilo Ruby Omakase
bin/brakeman              # análisis estático de seguridad
bin/bundler-audit         # comprobación de gemas vulnerables conocidas
bin/ci                    # ejecuta la suite de CI completa en local
```

## Despliegue

Se incluye un `Dockerfile`, así que la app se puede construir y ejecutar como
contenedor. El andamiaje de Kamal por defecto de Rails (`config/deploy.yml`,
`.kamal/`) también está presente, pero **aún no está configurado**: no hay
servidores ni registry definidos. Rellena `config/deploy.yml` y los secretos
antes de intentar un despliegue con Kamal.

Como la caché, los jobs y Action Cable corren todos sobre SQLite mediante los
adaptadores `solid_*`, basta con un único contenedor con un volumen persistente
para `storage/`: no hace falta ni Redis ni un servidor de base de datos externo.

## Estado

El lector de módulos en Ruby puro y el visor están en su sitio, junto con la
mesa de juego en tiempo real (partidas, jugadores, fichas, mazos, dados y chat
sobre Action Cable). Los módulos los sube un administrador y se importan de
forma asíncrona.

## Notas

VASSAL y sus módulos son obra del [proyecto VASSAL](https://vassalengine.org/) y
de los respectivos autores de cada módulo. Suel solo lee módulos
existentes; no los crea ni los distribuye.

El nombre *Suel* es la antigua ciudad romana que se alzaba sobre el cerro de
Fuengirola (Málaga), de donde es el autor.

Sí, está hecho con IA: Claude Fable (los dos días que estuvo disponible
públicamente) y Opus desde entonces.
