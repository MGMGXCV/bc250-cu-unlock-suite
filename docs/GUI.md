# Optional graphical mode / Modo gráfico opcional

BC-250 CU Unlock Suite remains a CLI-first project. The graphical mode is an **optional
beginner-friendly guide** that uses the exact same CLI underneath.

The GUI does not contain a second implementation of WGP writes. It never accepts
arbitrary shell commands from the browser and does not write AMDGPU registers
itself. Every hardware-changing button launches a whitelisted `bc250-unlock`
command in a **visible terminal** where `sudo`, warnings, progress, questions and
full output remain visible.

---

## Español

### Objetivo

El modo gráfico está pensado para personas con poca experiencia en Linux que se
sienten más cómodas siguiendo botones, explicaciones y pasos visuales. El modo
terminal tradicional sigue siendo el modo principal y no pierde ninguna función.

Iniciar la interfaz **sin sudo**:

```bash
./bc250-unlock gui
```

La herramienta abre una interfaz local en el navegador predeterminado. El
servidor sólo escucha en `127.0.0.1`; no publica la interfaz en la red local ni en
Internet.

La pantalla ofrece:

- selector Español / English;
- estado básico de plataforma, setup, GPU, CPU y persistencia;
- asistente completo recomendado;
- flujo paso a paso: doctor → baseline → compute → visual → combinado → soak →
  persistencia;
- herramientas de estado, report, recuperación y vuelta a stock;
- sección CPU visible con estado 6c/12t vs 8c/16t, unlock, quick y deep;
- control avanzado de re-arm automático de CPU, desactivado por defecto y con aviso explícito de que todavía requiere un warm reboot;
- botones SteamOS Verify / Repair sólo cuando se detecta SteamOS;
- advertencias adicionales antes de acciones que escriben routing o persistencia;
- terminal visible para cada comando;
- copia manual del comando si no se detecta una terminal compatible.

### Acceso desde el menú de aplicaciones

Instalar para el usuario actual:

```bash
./bc250-unlock gui-shortcut install
```

Después debería aparecer **BC-250 CU Unlock Suite** en el lanzador de aplicaciones del
escritorio.

Eliminarlo:

```bash
./bc250-unlock gui-shortcut remove
```

Si se mueve la carpeta del repositorio después de instalar el acceso, elimina y
vuelve a instalar el acceso para actualizar la ruta.

### Terminales detectadas

El launcher intenta, por orden aproximado, `$TERMINAL`, Konsole, GNOME Console,
GNOME Terminal, XFCE Terminal, Kitty, Alacritty, Foot, Terminator y xterm. Si no
encuentra ninguna, no ejecuta nada oculto: muestra/copia el comando exacto para
que el usuario lo pegue manualmente.

### Modelo de seguridad

El navegador sólo puede solicitar identificadores de acción predefinidos, por
ejemplo `baseline`, `scan`, `visual`, `stock` o `persist_install`. El backend
mapea esos identificadores a comandos fijos. No existe un endpoint de “ejecutar
este texto como shell”.

El servidor usa un token aleatorio por sesión y sólo escucha en localhost. Las
acciones privilegiadas siguen pidiendo la contraseña mediante `sudo` dentro de
la terminal normal.

---

## English

### Goal

Graphical mode is for users with limited Linux experience who prefer buttons,
short explanations and a visible step-by-step flow. The traditional terminal
workflow remains the primary interface and keeps every feature.

Start the GUI **without sudo**:

```bash
./bc250-unlock gui
```

On SteamOS, use the GUI from **Desktop Mode**. Gaming Mode launch behavior is not currently claimed/tested.

It opens a local interface in the default browser. The server binds only to
`127.0.0.1`; it is not exposed to the LAN or the Internet.

The UI provides:

- Español / English selector;
- basic platform, setup, GPU, CPU and persistence status;
- recommended full wizard;
- step-by-step doctor → baseline → compute → visual → combined → soak →
  persistence flow;
- status, report, recovery and stock-restore tools;
- first-class CPU section with 6c/12t vs 8c/16t status, unlock, quick and deep actions;
- advanced automatic CPU re-arm control, off by default, with an explicit warning that a user-initiated warm reboot is still required;
- SteamOS Verify / Repair buttons only on SteamOS;
- extra confirmations before routing/persistence actions;
- a visible terminal for every CLI command;
- manual command copy fallback when no supported terminal is detected.

### Application-menu shortcut

Install it for the current user:

```bash
./bc250-unlock gui-shortcut install
```

Remove it:

```bash
./bc250-unlock gui-shortcut remove
```

If the repository directory is moved later, remove and reinstall the shortcut so
its absolute path is refreshed.

### Safety architecture

The browser can only request predefined action IDs such as `baseline`, `scan`,
`visual`, `stock`, `cpu_unlock`, `cpu_deep` or `persist_install`. The backend maps those IDs to fixed CLI
commands. There is deliberately no endpoint that executes arbitrary shell text.

The server uses a random per-session token and binds only to localhost.
Privileged actions continue to request the user's password through normal `sudo`
inside the visible terminal.

## CPU actions and automatic re-arm

The CPU section is intentionally independent from GPU protected mode. A user may
keep a validated persistent GPU WGP profile active while checking or validating
the CPU unlock.

The automatic CPU re-arm switch is an advanced control and is OFF by default.
Turning it on launches the canonical CLI command in a visible terminal, where the
deep-PASS gate and final confirmation are enforced. The switch never causes an
automatic reboot. After a true cold boot the current session still starts at
6c/12t; the service only re-arms the mask so the user can choose a later warm
reboot to activate 8c/16t.

See [CPU.md](CPU.md).

## Headless / browser-control options

Do not automatically open a browser:

```bash
./bc250-unlock gui --no-browser
```

The terminal prints the localhost URL. Keep the launcher terminal open while the
GUI is running; `Ctrl+C` stops it. The page also has a **Stop graphical mode**
button.

The GUI is built entirely with Python standard-library HTTP serving plus local
HTML/CSS/JavaScript. No Qt, GTK, Node.js, Electron or web framework is required
at runtime.

## Persistent/profile-aware mode

The GUI detects `bc250-cu-live-manager.service`. If boot persistence is enabled, it enters a protected mode and disables actions that conflict with live probing. This mirrors the CLI guard instead of letting beginners launch commands that are expected to fail. Status, results, reports, persistence status/removal and SteamOS maintenance stay available. The backend enforces the same restriction.

## Readability and protected mode

Protected persistent mode disables diagnostic controls, but it does **not** dim the surrounding text. Disabled buttons use their own high-contrast styling so instructions remain readable in both dark and light desktop themes.

## Safety and AI transparency

The GUI footer reminds users that this is an experimental hardware tool and should be used with a recovery path. The project also discloses that research synthesis, code/documentation drafting and packaging were developed with assistance from **OpenAI ChatGPT (GPT-5.6 Sol)**. Hardware acceptance/rejection decisions remain the responsibility of the human operator. See `SAFETY.md` and `ACKNOWLEDGEMENTS.md`.
