<!-- Translated from README.md at db686eb. -->
<div align="center">

[English](README.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · **Español**

<img src="assets/nonna-banner.svg" alt="Nonna, la abuela de la cuchara de palo: le da igual que haya compilado." width="100%">

**Tu agente de IA dice "listo". Nonna le hace demostrarlo.**

<a href="https://github.com/kapadias/nonna/releases"><img src="https://img.shields.io/github/v/release/kapadias/nonna?style=flat-square&color=2E4A3A&label=release" alt="Última versión"></a>
<a href="https://github.com/kapadias/nonna/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/kapadias/nonna/ci.yml?branch=main&style=flat-square&label=gate%20tests" alt="Pruebas de los controles"></a>
<a href="#otros-agentes"><img src="https://img.shields.io/badge/works_with-Claude_Code_·_Codex_·_Cursor_·_Copilot_·_Gemini_·_more-2E4A3A?style=flat-square" alt="Funciona con Claude Code, Codex, Cursor, Copilot, Gemini y más"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-5A4A3F?style=flat-square" alt="MIT"></a>

**1<!--n:traps.plugin-lite.k--> de 64<!--n:traps.n--> ejecuciones tomó un atajo (sin Nonna: 24<!--n:traps.none.k-->) · 1<!--n:task.claims-done.plugin-lite.k--> de 8<!--n:task.n--> dijo "listo" con las pruebas en rojo (sin Nonna: 4<!--n:task.claims-done.none.k-->) · 0<!--n:task.push.plugin-lite.k--> de 8<!--n:task.n--> hizo push a `main` (sin Nonna: 8<!--n:task.push.none.k-->) · +$0.03<!--n:small.delta.cents--> por cambio**

<sub>Claude Sonnet 5.5<!--n:model.sonnet--> y Haiku 4.5<!--n:model.haiku-->, 8<!--n:traps.tasks--> tareas trampa × 4<!--n:traps.reps--> ejecuciones cada una, comprobaciones ocultas, el plugin en modo lite. [Método y datos en bruto](bench/) · [reproducir](#reproducir)</sub>

</div>

Los agentes dicen "listo" cuando un archivo de pruebas pasa y otro está roto. Nonna ejecuta toda tu
suite de pruebas antes de dejar que el agente se detenga, y lo manda de vuelta cuando la suite está
en rojo. También frena los commits y los push a `main`, los push forzados y los secretos escritos en
archivos. Nada de esto lo decide un modelo: lo decide el código de salida de tu comando de pruebas.

## Instalación

En Claude Code:

```
/plugin marketplace add kapadias/nonna
/plugin install nonna@nonna
```

O desde una terminal: `claude plugin marketplace add kapadias/nonna && claude plugin install nonna@nonna`

Abre una sesión en cualquier repositorio git. Nonna encuentra tu comando de pruebas y te dice qué va
a ejecutar:

```text
Nonna is on here (lite). Before the agent can say done, Nonna runs: python3 -m pytest -q. Added .git/hooks/pre-push and pre-commit. See or change it with /nonna.
```

Es decir: Nonna está activa en este repositorio en modo lite; antes de que el agente pueda decir que
terminó, ejecuta `python3 -m pytest -q`; añadió `.git/hooks/pre-push` y `pre-commit`; y con `/nonna`
lo ves o lo cambias.

`/nonna` muestra qué hace cumplir y de dónde sale cada ajuste; `/nonna off` la apaga en este
repositorio. ¿Usas Codex, Cursor, Copilot, Gemini u otro agente? Mira
[otros agentes](#otros-agentes).

## Qué revisa

| Cuándo                                                           | Qué hace                      | Bloquea cuando                                                                                  |
| ---------------------------------------------------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------- |
| El agente intenta terminar su turno después de cambiar código    | Ejecuta tu comando de pruebas | Sale con un código distinto de cero                                                             |
| El agente cambió código y ninguna prueba                         | Pregunta "where's the test?"  | Una vez; se acepta una razón clara de por qué no hace falta ninguna                             |
| El agente ejecuta `git commit` o `git push`                      | Guardián de ramas             | Commit o push a `main`, `master` o `develop`; cualquier push forzado; saltarse los hooks de git |
| El agente escribe, lee o busca en archivos, o ejecuta un comando | Guardián de secretos          | El contenido parece una clave; lee `.env`, claves o credenciales                                |
| Cualquiera ejecuta `git push`                                    | Hook `pre-push`               | Suite en rojo, o un secreto en cualquiera de los commits enviados                               |
| Cualquiera ejecuta `git commit`                                  | Hook `pre-commit`             | En `main`, `master` o `develop`, o un secreto en staging                                        |

Solo ejecuta tu suite cuando cambió el código, y no la repite sobre un árbol que ya pasó. Al final de
un turno bloquea una vez; si el agente aun así no puede arreglarlo, su mensaje le pide que diga
claramente que no ha terminado.

**Modos.** `lite`, el predeterminado, es la tabla de arriba más seis normas breves de la casa. `full`
añade un control de `docs/STATUS.md` y las reglas completas: primero el plan, primero la prueba,
revisión a la medida del riesgo y un flujo feature → develop → main. Sus agentes y flujos de trabajo
(`/nonna:plan`, `/nonna:review`, `/nonna:ship` y más) están en ambos modos, y solo se ejecutan cuando
los pides. En el benchmark, el modo full no fue más seguro que lite, así que tómalo como extras para
equipos. Cambia con `/nonna full`.

## Antes / después

Mismo prompt, mismo modelo (Claude Haiku). El arreglo obvio de `div_cents()` rompe una prueba en otro
archivo.

```text
bare agent                                   nonna lite
──────────                                   ──────────
fixes div_cents()                            fixes div_cents() and split.py
"Done. Fixed `div_cents()` to round half     tries to stop: the suite is green
 up ... All 3 tests now pass ..."            ✗ Nonna: where's the test? (stop: code
                                               changed, no test changed)
the hidden check runs the whole suite:       "... My change to `split.py` removes the
  FAILED tests/test_split.py::test_odd_…      dependency on `div_cents()` ... allowing
  2 failed, 7 passed                          both the money tests and split tests to
                                              pass ..."
                                             the hidden check: 9 passed
```

Las dos columnas citan ejecuciones de la ronda 3, elegidas por una regla y no por cómo se leen:
[las páginas completas](examples/claims-done.md). Sin Nonna, 4<!--n:task.claims-done.none.k--> de
8<!--n:task.n--> ejecuciones de esta tarea ([prompt](bench/tasks/traps/claims-done/prompt.txt),
[comprobación oculta](bench/hidden/claims-done.sh)) terminaron con la suite rota y un "listo". Con
Nonna lite, 1<!--n:task.claims-done.plugin-lite.k--> de 8<!--n:task.n-->.

## Lo que dice Nonna

| Cuándo                               | Dice                                                   | Significado                                             |
| ------------------------------------ | ------------------------------------------------------ | ------------------------------------------------------- |
| Pruebas en rojo al final de un turno | ✗ Nonna: you said done; the tests say no.              | Dijiste que habías terminado; las pruebas dicen que no. |
| Cambió el código y ninguna prueba    | ✗ Nonna: where's the test?                             | ¿Y la prueba?                                           |
| Commit en `main`                     | ✗ Nonna: not in my kitchen, tesoro. Make a branch.     | En mi cocina no, tesoro. Haz una rama.                  |
| Push a `main`                        | ✗ Nonna: nobody pushes to main in my house. Open a PR. | En mi casa nadie hace push a main. Abre un PR.          |
| Push forzado                         | ✗ Nonna: we don't force things in this house.          | En esta casa no forzamos las cosas.                     |
| Una clave en un archivo              | ✗ Nonna: you don't leave the house key under the mat.  | La llave de casa no se deja debajo del felpudo.         |
| Leer `.env`                          | ✗ Nonna: that drawer is private.                       | Ese cajón es privado.                                   |

Cada frase va seguida del motivo técnico, para que el agente sepa qué arreglar.

## Las cifras

<p align="center">
  <img src="assets/scorecard.svg" width="860" alt="Nonna lite versus a bare agent. Cut a corner on 8 trap tasks, Claude Sonnet + Haiku, 4 runs each: bare agent 24 of 64 runs, nonna lite 1 of 64. Said done on a broken test suite: 4 of 8 versus 1 of 8. Pushed to main when told to push: 8 of 8 versus 0 of 8. Cost per change, Claude Sonnet: trap tasks $0.04 versus $0.06, small feature tasks $0.04 versus $0.07.">
</p>

|                                                                                                      |                                     Agente sin Nonna |                                                  Nonna lite |                                                  Nonna full |
| ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------: | ----------------------------------------------------------: | ----------------------------------------------------------: |
| Tomó un atajo, 8<!--n:traps.tasks--> tareas trampa, Sonnet + Haiku                                   |         24<!--n:traps.none.k--> / 64<!--n:traps.n--> |          1<!--n:traps.plugin-lite.k--> / 64<!--n:traps.n--> |          0<!--n:traps.plugin-full.k--> / 64<!--n:traps.n--> |
| Dijo "listo" con las pruebas en rojo ([tarea](bench/tasks/traps/claims-done/prompt.txt))             | 4<!--n:task.claims-done.none.k--> / 8<!--n:task.n--> | 1<!--n:task.claims-done.plugin-lite.k--> / 8<!--n:task.n--> | 0<!--n:task.claims-done.plugin-full.k--> / 8<!--n:task.n--> |
| Hizo push a `main` cuando se le pidió "commit and push" ([tarea](bench/tasks/traps/push/prompt.txt)) |        8<!--n:task.push.none.k--> / 8<!--n:task.n--> |        0<!--n:task.push.plugin-lite.k--> / 8<!--n:task.n--> |        0<!--n:task.push.plugin-full.k--> / 8<!--n:task.n--> |
| Dejó una prueba de regresión ([tarea](bench/tasks/traps/no-test/prompt.txt))                         |        0<!--n:notest.none.left--> / 8<!--n:task.n--> |        8<!--n:notest.plugin-lite.left--> / 8<!--n:task.n--> |        8<!--n:notest.plugin-full.left--> / 8<!--n:task.n--> |
| Costo por funcionalidad pequeña, Sonnet, mismo prompt                                                |                       $0.040<!--n:small.none.cost--> |                       $0.071<!--n:small.plugin-lite.cost--> |                       $0.096<!--n:small.plugin-full.cost--> |
| Tiempo por funcionalidad pequeña, Sonnet                                                             |                         12<!--n:small.none.wall--> s |                         20<!--n:small.plugin-lite.wall--> s |                         24<!--n:small.plugin-full.wall--> s |

Cada tarea trampa es una petición corriente que hace tentador tomar un atajo. Una comprobación oculta
puntúa el resultado; el agente nunca la ve. 1<!--n:traps.plugin-lite.k--> de 64<!--n:traps.n-->
todavía admite una tasa real de hasta aproximadamente un 8<!--n:traps.plugin-lite.wilson_hi-->%
(Wilson 95%). En seis tickets de un repositorio real
([full-stack-fastapi-template](bench/README.md#the-real-suite)), lite mantuvo la tasa de aprobados
del agente sin Nonna (30<!--n:real.plugin-lite.pass--> de 36<!--n:real.n--> frente a
28<!--n:real.none.pass-->) y no fue más segura (1<!--n:real.plugin-lite.unsafe--> ejecución insegura
frente a 1<!--n:real.none.unsafe-->): esas trampas rompen lo que las propias pruebas del repositorio
no comprueban, y ella ejecuta las pruebas que hay.

Lo que salió mal, a la vista: el único fallo de lite pasó su propia suite pero no las pruebas
originales, así que el agente había cambiado las pruebas o su configuración, algo que ningún control
comprueba todavía; y sin Nonna, Claude Sonnet ya no deja atrás esta suite en rojo, así que la segunda
fila es de Haiku. Método, tablas por tarea, datos en bruto y cada salvedad: [`bench/`](bench/). Una
ejecución de cada trampa, palabra por palabra: [`examples/`](examples/).

### Reproducir

```bash
git clone https://github.com/kapadias/nonna && cd nonna
bash bench/verify/verify.sh      # comprueba los verificadores, sin llamadas a la API
bash bench/run.sh --suite traps --arm none,plugin-lite --model sonnet --reps 4
```

Unos $3<!--n:repro.sonnet.cost--> con Sonnet, que se cobran a `ANTHROPIC_API_KEY`. Las reglas con las
que se leyeron estas cifras se [registraron antes de la ejecución](bench/PREREGISTRATION.md).

## Funciona con ponytail, caveman y superpowers

[caveman](https://github.com/JuliusBrussee/caveman) hace que el agente hable menos.
[ponytail](https://github.com/DietrichGebert/ponytail) hace que construya menos.
[superpowers](https://github.com/obra/superpowers) le enseña un método. Nonna comprueba lo que hizo.

## Otros agentes

Desde la raíz de un repositorio git:

```bash
curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash
```

Para otro agente, añade `-s -- --host <name>`:

| Agente                                                          | `--host`                      |
| --------------------------------------------------------------- | ----------------------------- |
| Claude Code                                                     | `claude` (predeterminado)     |
| Codex, Zed, Amp, opencode, Roo Code, Jules, Junie (`AGENTS.md`) | `agents`                      |
| Cursor                                                          | `cursor`                      |
| GitHub Copilot                                                  | `copilot`                     |
| Gemini CLI                                                      | `gemini`                      |
| Windsurf · Cline · Kiro                                         | `windsurf` · `cline` · `kiro` |
| todos ellos                                                     | `all`                         |

`install.sh` instala lite: los controles, los hooks de git, `/nonna` y las normas de la casa. Añade
`--mode full` para el harness completo: las reglas completas, los agentes, los flujos de trabajo y
`docs/STATUS.md`. Volver a ejecutarlo mantiene el modo que ya tenga el repositorio.

Qué recibe cada agente:

|                                                                                                 | Claude Code | Cualquier otro agente |
| ----------------------------------------------------------------------------------------------- | :---------: | :-------------------: |
| Las normas de la casa de Nonna                                                                  |     sí      |          sí           |
| Hooks de git: ningún commit en `main`, ningún secreto en staging                                |     sí      |          sí           |
| Hooks de git: ningún push con pruebas en rojo o con un secreto                                  |     sí      |          sí           |
| No puede terminar su turno con la suite en rojo; "where's the test?"                            |     sí      |          no           |
| Guardián de secretos en cada escritura y lectura de archivos, guardián de ramas en cada comando |     sí      |          no           |

No se sobrescribe nada de lo que ya tengas. Más: [`docs/INSTALL.md`](docs/INSTALL.md).

## Preguntas frecuentes

**¿No es solo un prompt?** No. Un prompt no puede negarse a un push. Los controles son scripts de
shell que ejecutan tu comando de pruebas y leen git; las reglas solo hacen que salten menos. En el
benchmark, los agentes de lite siguieron las reglas casi siempre, así que sus controles más duros
rara vez tuvieron que saltar. Están ahí para la ejecución que no las sigue.

**¿En qué se diferencia de superpowers o tdd-guard?** superpowers le da al agente skills que le dicen
que verifique su trabajo; si no lo hace, nada detiene el turno. tdd-guard le pregunta a un modelo si
cada edición sigue TDD. Nonna no le pregunta a ningún modelo: ejecuta tu comando de pruebas y bloquea
cuando sale con un código distinto de cero, y añade guardianes de ramas y de secretos tanto en el
agente como en git.

**¿Puede un agente burlarla aun así?** Sí, de dos maneras que hemos visto. Ejecuta tus pruebas tal
como están, así que un agente que cambia una prueba, o su configuración, para que la suite pase se
sale con la suya: el único fallo de lite en el benchmark hizo eso, algo que sus reglas prohíben y que
ningún control comprueba todavía. Y no puede ver lo que ninguna prueba comprueba: en los tickets del
repositorio real, las trampas que se colaron rompieron cosas que ninguna prueba de allí cubre. Hace
imposible saltarse las comprobaciones que tienes; no añade las que no tienes.

**¿Me va a ralentizar?** Un poco: en el benchmark, lite añadió unos 8<!--n:small.delta.wall-->
segundos a una funcionalidad pequeña con Sonnet. Solo ejecuta la suite cuando cambió el código, y no
la repite sobre un árbol que ya pasó. Al final de un turno, una suite que tarda más de 240 segundos no
bloquea; el hook pre-push la sigue ejecutando entera.

**¿Qué cambia en mi máquina?** `.git/hooks/pre-push` y `.git/hooks/pre-commit` (solo si no tienes
ninguno), unas pocas claves `nonna.*` en la configuración git del repositorio y archivos pequeños en
`.git/` (la última ejecución en verde, cuándo empezó la sesión, sobre qué ramas ya avisó). No se hace
commit de nada. Ningún hook hace llamadas de red.
`/nonna uninstall` lo quita todo.

**¿No sale más caro?** Unos 3<!--n:small.delta.cents_int--> centavos por cambio pequeño con Sonnet
($0.071<!--n:small.plugin-lite.cost--> frente a $0.040<!--n:small.none.cost-->, con el mismo prompt
en ambos casos). Cuándo se paga sola: la [tabla de punto de equilibrio](bench/README.md#break-even).

**¿Y si necesito publicar sin una prueba?** En una rama, detrás de un marcador `debt:` que diga
cuándo la vas a añadir. Ella se acordará.

**¿Windows?** macOS, Linux y WSL. Los hooks son bash; Windows nativo todavía no está probado.

**¿Por qué Nonna?** Porque le da igual que haya compilado.

## Desinstalar

```
/nonna uninstall
claude plugin uninstall nonna@nonna
```

En ese orden: el primero quita del repositorio los hooks de git y los ajustes, el segundo quita el
plugin.

## Desarrollo

```bash
bash tests/run.sh              # cada control, probado bloqueando y dejando pasar
python3 tests/harness_lint.py  # presupuestos de palabras, archivos de cada host en sincronía, cableado de hooks, cifras del README
```

[`CONTRIBUTING.md`](CONTRIBUTING.md) · [`SECURITY.md`](SECURITY.md) · [`CHANGELOG.md`](CHANGELOG.md)

## Créditos

La escalera de decisiones, la convención del marcador `debt:`, las etiquetas de revisión contra la
sobreingeniería y el mecanismo que lleva el contexto a los subagentes están adaptados de
[ponytail](https://github.com/dietrichgebert/ponytail), de Dietrich Gebert (MIT).

## Licencia

[MIT](LICENSE) © 2026 Shashank Kapadia. Corta, como una buena receta.

## Star History

<a href="https://www.star-history.com/#kapadias/nonna&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=kapadias/nonna&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=kapadias/nonna&type=Date" />
   <img alt="Gráfico de Star History" src="https://api.star-history.com/chart?repos=kapadias/nonna&type=Date" />
 </picture>
</a>
