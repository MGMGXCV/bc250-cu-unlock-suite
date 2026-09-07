# BC-250 CU Unlock Suite — Español

**Descubre. Prueba. Desbloquea.**

Pruebas experimentales y reversibles de CUs/WGPs de GPU y desbloqueo validado de CPU 6c/12t -> 8c/16t para AMD BC-250 en Linux.

[English README](README.md)

La BC-250 expone normalmente 24/40 CUs. Este proyecto **no activa las 40 a
ciegas**: descubre el mapa real de fábrica de cada placa, prueba los WGP ocultos
de 2 CUs uno a uno, exige una comprobación visual humana y valida la combinación
final antes de ofrecer persistencia opcional.

> **Advertencia:** las escrituras de bajo nivel pueden congelar la GPU o el PC.
> Guarda tu trabajo antes de probar. Los WGP ocultos pueden estar físicamente
> dañados. Nunca copies el perfil WGP de otra BC-250.

Usa esta herramienta con responsabilidad: mantén una vía de recuperación y no
instales persistencia hasta haber superado compute, comprobación visual, juegos
reales y soak. Consulta [SAFETY.md](SAFETY.md).

> **Transparencia sobre IA:** BC-250 CU Unlock Suite se ha desarrollado con ayuda de
> **OpenAI ChatGPT (GPT-5.6 Sol)** para síntesis de investigación, estrategia de
> pruebas, borradores de código/documentación y empaquetado. Las observaciones y
> decisiones sobre el hardware deben seguir siendo validadas por una persona.
> OpenAI no patrocina ni respalda este proyecto. Consulta
> [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).

## Modo gráfico para usuarios menos experimentados

El proyecto sigue funcionando completamente desde terminal, pero incluye una
interfaz gráfica opcional **Español / English**.

Después de clonar/extraer el proyecto:

```bash
./setup.sh
./bc250-unlock gui
```

**No uses sudo para iniciar la GUI.** Las acciones que necesiten permisos abren
una terminal visible y solicitan `sudo` allí.

En SteamOS, usa la GUI desde **Desktop Mode**; no se promete compatibilidad de lanzamiento desde Gaming Mode todavía.

La interfaz explica y guía:

1. comprobación del hardware;
2. baseline stock de 24 CUs;
3. escaneo compute WGP por WGP;
4. comprobación visual usando el escritorio real;
5. revisión de resultados;
6. validación combinada;
7. soak test de 30 minutos;
8. persistencia opcional sólo cuando todo ha pasado.

Para añadir un acceso al menú de aplicaciones:

```bash
./bc250-unlock gui-shortcut install
```

Más detalles: [docs/GUI.md](docs/GUI.md).

## CachyOS / Arch

Ruta actualmente validada en hardware:

```bash
./setup.sh --os cachyos
sudo ./bc250-unlock wizard
```

## SteamOS

Ruta **experimental** porque SteamOS usa una imagen atómica/read-only:

```bash
./setup.sh --os steamos
sudo ./bc250-unlock wizard
```

Después de una actualización de SteamOS:

```bash
sudo ./bc250-unlock steamos verify
# sólo si detecta componentes ausentes:
sudo ./bc250-unlock steamos repair
```

Consulta [docs/STEAMOS.md](docs/STEAMOS.md).


## Compatibilidad con versiones anteriores

Desde v0.4.0 el comando principal es `./bc250-unlock`. Se conserva
`./bc250-lab` como alias de compatibilidad para que notas o scripts antiguos no
dejen de funcionar de golpe. La documentación nueva usa `bc250-unlock`.

En SteamOS algunos directorios internos conservan el nombre histórico
`bc250-wgp-lab` para no romper estados/persistencia creados por las versiones
0.2/0.3. Es sólo un detalle interno; el nombre público del proyecto es
**BC-250 CU Unlock Suite**.

## Comandos principales

```bash
sudo ./bc250-unlock doctor
sudo ./bc250-unlock wizard
sudo ./bc250-unlock baseline
sudo ./bc250-unlock scan
sudo ./bc250-unlock visual
sudo ./bc250-unlock results
sudo ./bc250-unlock apply
sudo ./bc250-unlock status
sudo ./bc250-unlock stock
sudo ./bc250-unlock recover
sudo ./bc250-unlock soak 30
sudo ./bc250-unlock report
sudo ./bc250-unlock cpu status
sudo ./bc250-unlock cpu unlock
sudo ./bc250-unlock cpu quick
sudo ./bc250-unlock cpu deep
sudo ./bc250-unlock cpu rearm status
```

Persistencia GPU, únicamente tras pruebas reales y soak limpios:

```bash
sudo ./bc250-unlock persist status
sudo ./bc250-unlock persist install
```

Rollback:

```bash
sudo ./bc250-unlock persist remove
```

La persistencia no modifica BIOS/firmware. Guarda el routing validado para **esa
placa concreta** y lo reaplica mediante el mecanismo systemd del live-manager.

## Desbloqueo de CPU — 6c/12t a 8c/16t

Desde v0.5.0 el desbloqueo de CPU deja de estar escondido como helper de
investigación y pasa a ser una función documentada de primer nivel. Sigue siendo
independiente del desbloqueo de CUs de GPU.

```bash
sudo ./bc250-unlock cpu status
sudo ./bc250-unlock cpu unlock
# reinicio en caliente cuando quieras activarlo, después:
sudo ./bc250-unlock cpu quick
sudo ./bc250-unlock cpu deep
```

La suite delega la operación volátil conocida `0x77 -> 0xFF` al
`bc250-cu-live-manager` descargado durante el setup. Tras un corte completo de
corriente la CPU vuelve a 6c/12t; después de armar el unlock, un reinicio en
caliente permite enumerar 8c/16t. El helper nunca reinicia el equipo
automáticamente.

### Re-arm automático avanzado

El re-arm está **desactivado por defecto** y sólo puede activarse después de un
`cpu deep` completo con PASS en los cores físicos 3 y 7 y en la prueba de todos
los hilos.

```bash
sudo ./bc250-unlock cpu rearm status
sudo ./bc250-unlock cpu rearm enable
sudo ./bc250-unlock cpu rearm disable
```

El re-arm **no elimina el reinicio necesario**. Después de un arranque en frío,
Linux entra en 6c/12t, el servicio rearma automáticamente la máscara y evita que
tengas que ejecutar `cpu unlock` a mano. La sesión actual sigue en 6c/12t hasta
que **tú decidas hacer un warm reboot**. La suite nunca reinicia sola.

El flujo de v0.5.0 se ha validado en la placa de desarrollo con quick/deep,
juegos reales, recuperación mediante corte completo de corriente y un nuevo
desbloqueo posterior. Es evidencia de una placa concreta, no una garantía para
todas las BC-250.

Más detalle: [docs/CPU.md](docs/CPU.md).

## Por qué existe la comprobación visual

Durante el desarrollo encontramos WGPs que daban `PASS` en compute pero
producían cuadrados azules/corrupción al mover el ratón y usar Plasma. Por eso un
WGP sólo se considera aprobado cuando pasa **compute + comprobación visual**. Una
corrupción visible siempre tiene prioridad sobre un PASS sintético.

## Estado del proyecto

- CachyOS / Arch: ruta validada en BC-250 real.
- SteamOS: experimental, basada en el mismo método live pero pendiente de más
  validación en hardware.
- GUI: capa opcional; nunca escribe registros por sí misma y siempre lanza el CLI
  canónico en una terminal visible.

El proyecto sigue marcado como experimental porque el estado físico de los WGP
es distinto en cada BC-250.

### Si ya tienes un perfil persistente

Cuando la persistencia al arranque está activada, el modo gráfico entra en **modo persistente protegido**. El flujo de diagnóstico (asistente, baseline, escaneos, validación combinada y soak) queda desactivado porque el CLI se niega deliberadamente a hacer probing mientras el servicio de restauración está activo. Estado, resultados, informes y gestión de persistencia siguen disponibles. Para volver a investigar WGPs ocultos, elimina primero la persistencia y vuelve a un routing stock limpio.

## Referencias, créditos y licencia

El proyecto no reclama como propios los descubrimientos base del desbloqueo de
CUs. Los créditos y fuentes principales están en
[docs/REFERENCES.md](docs/REFERENCES.md) y [THIRD_PARTY.md](THIRD_PARTY.md).

La licencia recomendada para el código propio de BC-250 CU Unlock Suite es **MIT**:
sencilla, permisiva y con cláusula AS-IS/sin garantía. Las herramientas upstream
que `setup.sh` descarga conservan sus propias licencias y no quedan relicenciadas
por este repositorio. Consulta [LICENSE](LICENSE) y
[docs/LICENSING.md](docs/LICENSING.md).

Para más detalle sobre responsabilidad y seguridad: [SAFETY.md](SAFETY.md).
