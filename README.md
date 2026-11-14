# Short Fights

FPS 1 vs 1 (máx. 2 personas reales por red local) con bots. Modos: **Equipos** (mismos bots por equipo) o **Todos contra todos**. 3 mapas sin texturas: Almacén, Patio, Torres.

## Jugar en PC
Abre `project.godot` con `C:\Users\ROX\Desktop\Godot.exe` y pulsa F5.

| Acción | PC | Celular |
|---|---|---|
| Mover / mirar | WASD / ratón (clic para capturar) | joystick izquierdo / arrastrar a la derecha |
| Disparar / usar | clic izquierdo | FUEGO |
| Saltar / recargar | Espacio / R | SALTO / RECARGAR |
| Armas | 1 primaria · 2 pistola · 3 botiquín · 4 granada · Q siguiente | ARMA |
| Apuntar / correr | clic derecho / Shift | APUNTAR / joystick al máximo |
| Salir | Esc (2 veces) | X |

Partida entre 2: los dos en la misma Wi-Fi. Uno pulsa **Crear partida** (aparece su IP), el otro escribe esa IP y pulsa **Unirse**. El host pulsa **Empezar**. Puerto UDP 7777 (permite Godot en el firewall de Windows la primera vez).

Probar controles táctiles en PC: ejecuta con el argumento de usuario `-- --touch`.

## Exportar a Windows
Editor → Editor → Gestionar plantillas de exportación → Descargar (una vez). Proyecto → Exportar → "Windows Desktop".

## Compilar para iPhone 12
**Sin Mac (GitHub Actions):** sube el proyecto a GitHub → pestaña Actions → "iOS IPA (sin firmar)" → Run workflow (o crea un tag `v*`). Al terminar, descarga el artefacto `ShortFights-unsigned-ipa` y fírmalo con Sideloader. En repos privados, los minutos de macOS cuentan x10.

**Con Mac:**
Requisito de Apple: **macOS + Xcode**. No se puede firmar una app iOS desde Windows.
1. En un Mac (propio, prestado o alquilado en la nube, p. ej. MacinCloud): instala Xcode y Godot 4.7.2, abre el proyecto, descarga las plantillas de exportación.
2. Xcode → Settings → Accounts: inicia sesión con tu Apple ID (gratis sirve para tu propio iPhone; la app caduca a los 7 días). Copia tu Team ID.
3. Godot → Proyecto → Exportar → preset **iOS**: pega el Team ID en *App Store Team ID*, cambia el *Bundle Identifier* si quieres, y exporta (genera un proyecto Xcode).
4. Abre el `.xcodeproj` generado, conecta el iPhone por cable, activa Modo desarrollador en el iPhone (Ajustes → Privacidad y seguridad) y pulsa Run.
5. En el iPhone: Ajustes → General → VPN y gestión de dispositivos → confía en tu cuenta de desarrollador. Acepta el permiso de **red local** al abrir el juego (necesario para jugar con el PC).

El proyecto ya usa el renderer *Mobile*, compresión ETC2/ASTC y orientación horizontal.

## Modelos 3D
Personajes y armas: Toon Shooter Game Kit de Quaternius (CC0), en `assets/models/` (ver LICENSE.txt). Los sonidos se generan por código en `autoload/sfx.gd`.

## Desarrollo con Claude
`CLAUDE.md` = mapa y contrato del proyecto. Skill `godot-token-efficient-engineering` = método (orquestador + trabajadores Sonnet/Haiku). Verificación: `bash tools/check.sh`.
