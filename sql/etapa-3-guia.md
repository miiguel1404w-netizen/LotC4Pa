# Etapa 3 del Camino 1 — guía paso a paso

Esta etapa cierra los **permisos de escritura** de la base de datos: después
de aplicarla, solo quien entra con la **cuenta nueva** (las cuentas reales de
Supabase que se crearon en la etapa 1) puede crear, editar o borrar
**vendedores, sorteos, resultados y premiación**.

Hoy, cualquiera que copie la llave que está a la vista en el código puede
escribir y borrar en esas tablas. Eso es lo que se termina acá.

---

## Antes de empezar

- **El administrador tiene que poder entrar con su cuenta nueva.** Pruébalo
  antes de correr nada: cierra sesión, escribe `admin` y la contraseña de la
  cuenta real, entra, y en **Administración → Seguridad → Permisos de la base
  de datos** debe decir *"Entraste con la cuenta nueva"*.
- **Hazlo en un rato de poca venta**, con la app abierta en el celular para ir
  probando.
- Si un vendedor tiene delegado el módulo **🏆 Resultados y premiación**,
  también va a necesitar su cuenta nueva para poder guardar resultados. Los
  demás vendedores no necesitan nada: siguen vendiendo igual.

## Orden de los pasos

### 1. Subir primero el `index.html` de esta entrega

Es importante que vaya **antes** del SQL. Trae tres cosas que hacen falta para
esta etapa:

- Avisa claro (**"tu cuenta no tiene permiso…"**) cuando la base de datos
  rechaza un cambio. Con la versión anterior, un permiso cerrado se veía como
  si hubiera guardado bien aunque no guardara nada.
- Un letrero amarillo arriba para quien entró con el login viejo y necesita
  guardar cambios.
- El **probador de permisos** (Administración → Seguridad), para ir
  comprobando tabla por tabla.

Este `index.html` funciona igual con la base de datos **antes y después** del
SQL, así que se puede subir tranquilo.

### 2. Correr el SQL, bloque por bloque

Abre `sql/etapa-3-rls.sql` en el editor SQL de Supabase y corre **un bloque a
la vez**, en orden:

| Bloque | Qué cierra | Qué probar después |
|---|---|---|
| 0 | Nada — solo crea funciones de apoyo | Nada cambia todavía |
| 1 | `sorteos` | Editar un sorteo, pausarlo, y que un vendedor pueda anotar |
| 2 | `resultados` | Guardar un resultado y ver que se calculen los premios |
| 3 | `vendedores` | Crear, editar y borrar un vendedor de prueba |
| 4 | `app_config` | Cambiar un monto de premiación y guardarlo |

Cada bloque trae, en comentarios, su propia lista de pruebas y su **DESHACER**
por si algo sale mal. Si un bloque falla, corre su DESHACER y no sigas con el
siguiente.

Después de cada bloque, entra a **Administración → Seguridad → Probar
permisos**: con la cuenta nueva todo debe salir en ✅.

### 3. Comprobar que un vendedor normal sigue vendiendo

Con cualquier vendedor (con cuenta nueva o del login viejo):

- Puede iniciar sesión.
- Ve la lista de sorteos y los resultados.
- Puede anotar un ticket y le sale el comprobante.
- Se le puede anular un ticket.

Si algo de esto falla, **deshaz el último bloque que corriste** y avisa qué
pasó.

---

## Qué pasa si alguien entra con el login viejo

No pierde nada de lo que hacía antes: ve todo e igual vende. Lo único que ya
no puede hacer es guardar cambios en vendedores, sorteos, resultados y
premiación — y en ese caso la app se lo dice con todas las letras en vez de
fingir que guardó.

Al administrador, además, le aparece un letrero amarillo arriba recordándole
que entre con su cuenta nueva.

## Qué **no** se cerró todavía (y por qué)

- **La lectura de las tablas.** Mientras el login viejo siga encendido, la app
  necesita leer `vendedores` y `app_config` antes de que alguien inicie sesión
  (así es como compara la contraseña).
- **Las tablas donde escriben los vendedores en cada venta**: `folio_counter`,
  `ventas`, `liquidaciones`, `deudas_equipo`, `asistencia_equipo`,
  `coberturas`, `registro_cambios`, `push_subscriptions`. Cerrarlas mientras
  haya vendedores sin cuenta nueva dejaría a alguien sin poder vender, que es
  el peor error posible.

Las dos cosas son el trabajo de la **etapa 4**, que empieza por darle cuenta
nueva a todos los vendedores y recién después apaga el login viejo. Está
detallado al final de `sql/etapa-3-rls.sql`.
