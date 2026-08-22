# LotC4Pa — Documentación técnica del proyecto

Este documento explica cómo está armada la app, por qué se tomaron ciertas decisiones, y qué falta por hacer. Está pensado para que cualquier desarrollador o IA que continúe el proyecto pueda entenderlo sin depender de que alguien más se lo explique desde cero.

## Qué es

Una herramienta web para registrar ventas de lotería (banca de números), usada por un administrador y varios vendedores (algunos "de equipo", otros "independientes" con comisión). Genera comprobantes, calcula premios automáticamente, y lleva cuentas de comisiones. Volumen aproximado: ~500 tickets/día.

## Arquitectura

- **Todo el frontend vive en un solo archivo:** `index.html` (HTML + CSS + JavaScript juntos, sin build step, sin frameworks). Esto fue una decisión deliberada para simplificar el despliegue, no un descuido — pero significa que el archivo es grande (3,500+ líneas) y cualquier cambio requiere repasar el archivo completo.
- **Backend:** Supabase (Postgres + API REST vía supabase-js, cargado por CDN). Proyecto propio del dueño del negocio.
- **Hosting:** GitHub Pages, repo `miiguel1404w-netizen/LotC4Pa`. Desplegar = subir `index.html` (y a veces `manifest.json` / `sw.js`) por la interfaz web de GitHub ("Add file → Upload files").
- **App instalada en Android:** un APK generado con PWABuilder (tipo TWA — Trusted Web Activity, básicamente un navegador embebido apuntando a la GitHub Page), firmado con la app "AppSigner" directo desde el celular. Requiere un archivo `assetlinks.json` en un repo aparte (`miiguel1404w-netizen.github.io`, el repo de "usuario", no el del proyecto) para que no aparezca la barra de navegador.
- **iPhone:** el dueño accede por Safari con "Agregar a pantalla de inicio" (no usa APK, solo PWA).
- **Sin build step:** no hay npm/webpack/etc. Los cambios se hacen directo en el HTML y se suben tal cual.

## Base de datos (Supabase)

Tablas principales — todas con RLS habilitado:

| Tabla | Para qué | Notas |
|---|---|---|
| `vendedores` | Cuentas de vendedores | `password` guardado con hash SHA-256 (ver sección Seguridad); `en_equipo` boolean (false = independiente); `porcentaje` numeric (comisión, solo aplica si independiente) |
| `sorteos` | Catálogo de sorteos (nombre, horarios, días que juega) | `pale_habilitado`, `tipo_billete` ('ninguno'/'nacional'/'gordito'), `pausa_fecha` (oculta el sorteo solo por hoy sin borrarlo), `excepcion_fecha` (agrega un día extra fuera del horario normal), `icono_url` (link a imagen opcional) |
| `ventas` | Cada ticket vendido | `jugadas` es un JSONB con el array de jugadas del ticket; `codigo_sorteo` es un snapshot de texto (sobrevive aunque se borre el sorteo); `editado_por` guarda quién hizo la última edición |
| `resultados` | Números ganadores por sorteo/día | `sorteo_id` puede ser NULL (resultado "histórico" cuando el sorteo ya no existe) — en ese caso se usa `codigo_sorteo` para relacionar con las ventas; `primero_completo`/`segundo_completo`/`tercero_completo` guardan el número de 4 cifras completo (Chance usa solo los últimos 2 automáticamente) |
| `liquidaciones` | Libro de movimientos de Vendedores Independientes | Filas automáticas (una por vendedor/sorteo/día, generadas al guardar un resultado) tienen `codigo_sorteo` poblado y `direccion` NULL; filas manuales ("Pago"/"Abono") tienen `direccion` ('admin_a_vendedor'/'vendedor_a_admin') y `codigo_sorteo` NULL |
| `app_config` | Config global: usuario/contraseña admin, tabla de premios de cada modalidad | Fila única (`id=1`) |
| `folio_counter` | Contador del próximo número de folio | Fila única (`id=1`) |

**Todo el SQL histórico** (cada `alter table` / `create table` que se ha corrido) debería estar guardado en un archivo `schema.sql` aparte de este proyecto — si no lo tienes, pídele el historial de commits/SQL a quien traspase el proyecto. Desde la etapa 3 del Camino 1, el SQL nuevo sí vive en este repo, en la carpeta `sql/`.

## Reglas de negocio clave (para no repetir errores ya corregidos)

### Premiación — Chance ($0.20 y $0.25)
Se juega un número de 2 cifras. Se compara **directamente** contra el resultado real de cada posición (1ro/2do/3ro) — sin reordenar nada. Si el número coincide con **más de una posición** (ej. 1ro y 2do del resultado terminan igual), se pagan **todas** las que coincidan, sumadas — no solo la primera.

### Premiación — Palé ($1.00)
Se juega un número de 4 cifras, partido en 2 pares de 2. Gana si esos dos pares coinciden con (1ro,2do) o con (2do,3ro) del resultado, **en cualquier orden** — es decir, jugar "1245" y jugar "4512" es exactamente lo mismo para efectos de premiar.

### Premiación — Billete ($1.00, solo sorteos marcados Nacional/Gordito)
Se juega un número de 4 cifras. Se compara contra el número **completo** de 4 cifras de cada posición (1ro/2do/3ro), cada una con su propia tabla de premios (4 cifras / 3 cifras / 2 cifras). Reglas de coincidencia parcial:
- **3 cifras:** coinciden las primeras 3 O las últimas 3 — aplica igual en las 3 posiciones.
- **2 cifras:** en el **1er premio**, coinciden las primeras 2 O las últimas 2. En el **2do y 3er premio**, **solo** cuentan las últimas 2 (no las primeras) — esta asimetría viene de la tabla de premios real del negocio y es fácil de romper si alguien "simplifica" el código sin fijarse.
- Dentro de una misma posición se paga solo el nivel más alto que aplique (nunca se suman 4+3+2 de la misma posición).
- Entre posiciones distintas (1ro, 2do, 3ro) sí se suma si gana en varias.

### Vendedores Independientes — balance
Fórmula por cada fila automática (una por vendedor/sorteo/día): `vendido − comisión − premios que pagó = monto de esa fila`. El balance total es la suma de todas las filas (automáticas + manuales). Signo: positivo = el vendedor le debe al admin; negativo = el admin le debe al vendedor. Un "Abono" (vendedor entrega al admin) **resta**; un "Pago" (admin entrega al vendedor) **suma** — es un adelanto que el vendedor tiene que reponer.

**Importante:** las filas automáticas solo se generan en el momento en que se guarda el resultado de un sorteo — nunca antes. Si se corrige un resultado ya guardado, la fila correspondiente se actualiza sola (no se duplica). Hay un botón "🔄 Poner al día con resultados ya cargados" para regenerar filas de resultados viejos (por ejemplo, si se corrige la lógica de premiación después de que ya se premiaron sorteos).

## Seguridad — estado actual

Se identificó que la app expone la llave (`anon key`) de Supabase directamente en el código fuente (inevitable en cualquier app 100% frontend), y que originalmente las políticas RLS estaban completamente abiertas (`using(true) with check(true)` en todo). Se implementó una mitigación parcial ("Camino 2"):

- Las contraseñas se guardan con hash SHA-256 (no en texto plano). Las cuentas viejas se migran solas al hash en su próximo login exitoso (comparación intenta primero contra el hash, si falla intenta contra texto plano y si acierta ahí, actualiza el registro).
- Se quitó el permiso de `DELETE` externo en `ventas` y `liquidaciones` (dejando solo select/insert/update, que es todo lo que la app necesita — nunca borra esas dos tablas).

**"Camino 1" (el arreglo de fondo)** es pasar a autenticación real de Supabase (no el login "a mano" comparando contra la tabla `vendedores`) + políticas RLS por usuario. Toca el login de todos, así que se planeó por fases:

1. ✅ Crear cuentas de auth de Supabase para admin/vendedores, sin tocar el login actual.
2. ✅ Probar el login nuevo en paralelo (primero admin, luego 1-2 vendedores). El login intenta primero `signInWithPassword` con el correo interno `usuario@lotc4pa.app`; si esa cuenta no existe, sigue de largo al login viejo.
3. ✅ Cerrar permisos RLS tabla por tabla, probando cada una antes de seguir → ver más abajo.
4. ✅ (El paso de riesgo) apagar el login viejo y dejar el nuevo como único → ver más abajo.

No se debe hacer sin que el dueño esté despierto y disponible para probar — un permiso mal cerrado puede dejar a un vendedor sin poder entrar a vender.

### Etapa 4 (hecha) — login único y todo cerrado

**Aplicada en producción el 22 de agosto de 2026**, de madrugada, con la comprobación previa de que los 5 vendedores tenían cuenta real **y ya estaban entrando con ella** (`auth.users.last_sign_in_at` reciente en todos — que la cuenta exista no basta: si la contraseña no es la que la persona escribe, entra por el login viejo sin que nadie lo note).

SQL: `sql/etapa-4-rls.sql` (bloques 5 a 8, con su marcha atrás completa al final). Guía: `sql/etapa-4-guia.md`.

Qué cambió:

- **Una sola forma de entrar**: `signInWithPassword` contra la cuenta real. El correo se arma solo desde el usuario de siempre (`usuario@lotc4pa.app`), así que para el vendedor no cambió nada de lo que escribe. Se eliminó el login viejo, la comparación contra `vendedores.password` y la migración de contraseñas del Camino 2 (`migrar_password_legacy`, borrada).
- **Los datos se piden DESPUÉS de iniciar sesión.** Antes se cargaban al abrir la app, antes del login. Con la lectura cerrada eso traería todo vacío, así que el arranque ahora es: revisar sesión → si hay, cargar datos → identificar a la persona. Es el cambio estructural de esta etapa; si alguien vuelve a mover la carga antes del login, rompe la app entera.
- **Quién es cada quien sale de la sesión, no del celular.** `identificarUsuarioDeLaSesion()` deduce el rol del correo de la cuenta (la parte de antes del `@`). Lo guardado en `localStorage` quedó solo para rellenar el usuario en pantalla.
- **El canal en vivo de resultados se abre al entrar**, no al cargar la página: un canal abierto sin sesión no recibe nada con la lectura cerrada.
- **Todas las tablas exigen sesión** (`auth.uid() is not null`), cada una solo con las operaciones que la app realmente usa — `ventas` y `liquidaciones` siguen sin DELETE, como quedó en el Camino 2. El rol `anon` se quedó sin un solo permiso: la llave del código ya no sirve para nada.

⚠️ **Agregar un vendedor son dos pasos desde ahora**: crearlo en la app **y** crearle la cuenta en Supabase → Authentication (`usuario@lotc4pa.app`, con Auto Confirm User). Si falta el segundo, no puede entrar. La contraseña del formulario de la app ya no controla el acceso — se avisa en la propia pantalla.

Lo que **no** se hizo, y queda como posible etapa 5: filtrar por usuario *dentro* de cada tabla (que un vendedor solo pueda leer sus propias ventas, por ejemplo). Hoy cualquiera que haya iniciado sesión puede leer todas las filas de las tablas, que es justo lo que la app necesita para funcionar como funciona (el equipo comparte y anula tickets entre sí, y todo el filtrado es del lado del navegador). El riesgo que queda es de alguien de adentro usando la API a mano, no de cualquiera con la llave.

### Etapa 3 (hecha) — escritura cerrada en las tablas sensibles

**Ya está aplicada en producción (22 de agosto de 2026).** Los 5 bloques del SQL se corrieron en el Supabase real y se probaron uno por uno: el admin guarda con su cuenta nueva, y un vendedor entrando por el login viejo sigue vendiendo igual. **No hay que volver a correr ese SQL** — está guardado como referencia y para saber qué se cerró y cómo deshacerlo.

SQL: `sql/etapa-3-rls.sql` (en bloques, uno por tabla, cada uno con sus pruebas y su "deshacer"). Guía en lenguaje llano para aplicarlo: `sql/etapa-3-guia.md`.

Qué quedó cerrado: `vendedores`, `sorteos`, `resultados` y `app_config` solo aceptan **insert/update/delete** de quien entró con cuenta real de Supabase — el admin, o (solo para `resultados`) un vendedor que tenga delegado el módulo "🏆 Resultados y premiación". Además se le quitó al rol `anon` el permiso de escribir en esas cuatro tablas.

Piezas nuevas en la base de datos:
- `es_admin()`, `tiene_modulo(text)`, `correo_auth()`, `usuario_auth()`: funciones de apoyo que usan las políticas. La cuenta real se relaciona con la fila de `vendedores` por la parte de antes del `@` del correo (así se crearon en la etapa 1).
- `app_config.admins_auth` (jsonb) y `vendedores.auth_email` (text): escapes por si alguna cuenta real usa un correo que no sigue la convención `usuario@lotc4pa.app`.
- `migrar_password_legacy(usuario, plano, hash)`: mantiene viva la migración de contraseñas del Camino 2 ahora que el login viejo ya no puede escribir en `vendedores`/`app_config`. Solo cambia la contraseña si quien llama ya demostró saber la vieja. Se borra en la etapa 4.

Cambios en `index.html` que van con esta etapa:
- **`guardarEnBD(consulta, queSeIntentaba)`**: todo guardado en esas tablas pasa por acá. Importante entender por qué existe: Supabase **no lanza excepción** cuando RLS rechaza algo, y en `update`/`delete` normalmente **ni siquiera devuelve error** — simplemente no toca ninguna fila y todo "parece" que salió bien. La función pide las filas afectadas (`.select('id')`) y si no vino ninguna, avisa con un mensaje claro. Sin esto, un permiso cerrado se ve como un guardado exitoso, que es la peor forma de fallar de esta etapa.
- Letrero amarillo arriba para quien entra por el login viejo y necesita escribir (admin o vendedor con Resultados delegado).
- **Administración → Seguridad → Permisos de la base de datos**: dice con cuál cuenta entraste y tiene un botón "Probar permisos" que revisa lectura de las cuatro tablas y escritura en `sorteos` (reescribiendo el mismo valor que ya tenía, o sea sin cambiar nada). Sirve para ir probando bloque por bloque.
- El auto-login ya no devuelve la sesión en silencio si la última vez se entró con cuenta real y esa sesión venció: pide la contraseña otra vez, en vez de dejar al admin adentro sin poder guardar nada y sin entender por qué.

Lo que **sigue abierto a propósito** hasta la etapa 4:
- La **lectura** de todas las tablas: mientras exista el login viejo, la app tiene que leer `vendedores` y `app_config` antes de que alguien inicie sesión.
- Las tablas donde escriben los vendedores en cada venta: `folio_counter`, `ventas`, `liquidaciones`, `deudas_equipo`, `asistencia_equipo`, `coberturas`, `registro_cambios`, `push_subscriptions`. No se pueden cerrar hasta que todos los vendedores tengan cuenta real.

El detalle de qué correr en la etapa 4 está al final de `sql/etapa-3-rls.sql`.

## Decisiones de diseño que vale la pena conocer

- **Un solo HTML porque así se decidió empezar** — no por limitación técnica. Separar en archivos (HTML/CSS/JS) y pasar a un repo con historial de versiones más formal está planeado mas sin fecha.
- **Hora de cierre de sorteos usa hora del servidor** (Supabase RPC), no el reloj del celular — para que nadie adelante/atrase su reloj y siga anotando después de cerrado.
- **Cola de tickets sin conexión:** si se pierde la señal al anotar, el ticket se guarda en `localStorage` con un estado "⏳ Pendiente" y se reintenta solo al volver la señal (evento `online` del navegador + reintento en cada refresco de 30s). Usa `upsert` con un id generado una sola vez por venta (no `insert`), específicamente para que un reintento nunca cree un duplicado si la venta ya se había guardado pero la confirmación no llegó a tiempo — esto causó un incidente real de tickets duplicados antes de corregirse.
- **La consulta de ventas/resultados/liquidaciones a Supabase usa paginación manual** (bloques de 1000 filas) — Supabase corta a 1000 filas por defecto sin avisar, y esto causó que ventas viejas desaparecieran silenciosamente de la app cuando el negocio superó las 1000 ventas acumuladas.
- **Refresco automático cada 30 segundos** (no websockets/realtime) para mantener a todos los dispositivos más o menos sincronizados.
- **Bug conocido, dejado a propósito sin corregir** (decisión explícita del dueño): el filtro de fecha en Historial general compara texto tal cual contra la fecha formateada — si se escribe el año con 2 dígitos en vez de 4, no encuentra coincidencias. No se ha corregido porque el dueño pidió dejarlo así.

## Flujo típico de trabajo en este proyecto

1. Se identifica un cambio o bug (a veces con capturas de pantalla).
2. Se edita `index.html` directamente.
3. Se valida sintaxis de JS antes de entregar (Node `--check` sobre cada `<script>` extraído).
4. Se revisan referencias a IDs de HTML sin definir, e IDs duplicados.
5. Se entrega el archivo; el dueño lo sube a GitHub manualmente.
6. Si hubo cambios de base de datos, se entrega el SQL correspondiente para correr en el editor SQL de Supabase, **antes** de subir el archivo.
7. El dueño prueba en producción real (no hay ambiente de pruebas separado) y reporta si algo falla.

## Pendientes conocidos (sin construir todavía)

- RLS por usuario dentro de cada tabla (posible etapa 5, ver arriba). La autenticación real y el cierre de todas las tablas ya están hechos.
- Separar el proyecto en varios archivos + control de versiones formal con Git.
- Notificaciones push a vendedores cuando se carga un resultado.
- Un módulo "Modo Cobertura" (semáforo de riesgo por número vendido) se llegó a construir y luego se eliminó por decisión del dueño — quedó fuera del código por completo, no hay rastro de él.
