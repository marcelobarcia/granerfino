# Club Granero Fino · v3

## Sonidos, acceso de clientes y atención sin celular

- `sounds.js` sintetiza sonidos localmente con Web Audio: clics que desaceleran durante el giro y una melodía al mostrar el premio. El sonido solo se habilita por interacción del usuario. Control para silenciar en escritorio y móvil, preferencia guardada por dispositivo. Sin archivos externos ni autoplay al cargar.
- También hay giro visual y sonoro desde la ficha del miembro en Caja, para clientes que no usan celular.
- Nuevos registros eligen PIN de seis números. Vuelven con celular y PIN mediante “Ya soy miembro”. Miembros anteriores pueden crear PIN desde Mis premios. El PIN se almacena derivado con PBKDF2; hay límites de intentos por IP y celular.
- “Olvidé mi PIN” abre ayuda por WhatsApp. Caja → Miembros → Ver ficha → Recuperar acceso genera un enlace de un uso que vence en 15 minutos, después de que el operador verifica al cliente y el control del celular registrado. El mensaje se prepara exclusivamente para ese celular; el operador decide enviarlo. No se envían SMS ni WhatsApp automáticamente. Al usar recuperación se reemplazan accesos anteriores, preservando premios y sellos.
- “Registrar miembro” en Caja admite nombre y teléfono opcional. Los clientes sin celular reciben un número de socio GF-…; se buscan por nombre o número. Desde la ficha se registra la compra y se gira, usando las mismas reglas y evitando QR adicionales para esa compra. El canje también se inicia desde la ficha.
- Para una nueva instalación después de v2: `customer-access-schema.sql`, luego `customer-access-functions.sql`. Son copia del esquema y funciones ya aplicados, sin datos de personas ni secretos.
- Verificación: pruebas de alta con PIN, ingreso por otro acceso, recuperación de un solo uso, revocación, preservación de sellos y operaciones sin teléfono pasaron antes de la publicación interrumpida. La actualización de sonidos agrega `scripts/check-sounds.mjs` y revisión del giro en navegador.

## Actualización: tarjeta, parametría y miembros

- Caja → Configuración: activa o pausa sellos, define objetivo (2–20), compra mínima por sello, reinicio de tarjeta, tipo de premio especial (descuento o producto), descripción, monto del descuento, mínimo de canje y vigencia (1–365 días). Los valores iniciales son ejemplos de prueba, no una política comercial aprobada.
- Cada giro nuevo válido suma como máximo un sello, automáticamente y dentro de la misma transacción que entrega el descuento. Un QR repetido no agrega otro sello. Si la compra alcanza para la ruleta pero no para el mínimo de la tarjeta, no suma sello.
- Al completar la tarjeta se genera un único premio especial, disponible en Mis premios con código `GC-…`; los de la ruleta conservan `GF-…`. Configuración inicial de prueba: 5 sellos, mínimo $3.000 por sello, premio especial de descuento $1.500 en nueva compra desde $15.000, vigencia 30 días, reinicio habilitado.
- Cada tarjeta conserva sus reglas y su premio desde el primer sello. Cambios se aplican a tarjetas nuevas; pausar sellos no borra avances. No hay retroactividad sobre giros anteriores a esta actualización. Las tarjetas de prueba y reales se acumulan por separado. Si una tarjeta se definió sin reinicio, termina el recorrido al completarse.
- Los premios especiales se presupuestan aparte: el límite diario existente reserva únicamente descuentos de la ruleta. Un único beneficio por comprobante se controla mediante un registro común entre cupones y premios especiales. Los productos se entregan y registran manualmente en Odoo.
- Caja → Miembros: lista paginada, búsqueda por nombre o teléfono, filtro por consentimiento de novedades, ficha con tarjeta y premios, exportación CSV de la búsqueda completa. El modo de prueba/real filtra la lista. Los identificadores de acceso secreto nunca se exponen al panel.
- El frontend ahora usa también `dist/club-v2.js`; copiarlo junto al HTML si se aloja en GitHub Pages.
- Para una instalación nueva: aplicar `supabase/sql/schema.sql`, `defaults.sql`, `loyalty-v2.sql` y `loyalty-v2-card-order.sql`, en ese orden. La actualización fue aplicada a la instancia existente sin reemplazar datos ni accesos.
- Pruebas adicionales: `scripts/check-loyalty-v2.mjs` (API con sesión temporal por stdin), `scripts/check-loyalty-transactions.sql` (reglas, cambios durante una tarjeta y producto; todo revertido), `scripts/check-frontend-v2.mjs` (campos, tarjetas completas, premios producto y escape de HTML).

Primera versión: compra → QR único → ruleta → registro breve → Mis premios → canje en caja.

## Acceso público y caja

La aplicación se habilitó públicamente por solicitud del propietario. La zona Caja valida usuario `admin` y contraseña en servidor. El alta inicial se completó: el antiguo enlace de activación quedó deshabilitado. La contraseña elegida por el propietario se almacena derivada con PBKDF2 y nunca se incluye en el código o este documento. El modo de prueba se mantiene independiente del acceso público.

## Uso

- Abrir la aplicación sin parámetros para ver el club y su demostración.
- Abrir `?caja=1` para caja. La activación inicial usa un enlace privado de un solo uso; la contraseña de caja se configura allí (mínimo 12 caracteres).
- Caja carga número de comprobante y monto. Genera un QR de un solo uso; se puede mostrar o compartir el enlace por WhatsApp. No hay envíos automáticos.
- Cada QR dura siete días. El resultado se calcula en servidor, se guarda una sola vez y resiste doble clic/solicitudes concurrentes.
- El cliente registra nombre y celular chileno, acepta condiciones y opcionalmente novedades. Se guarda el acceso en ese navegador; puede copiar un enlace personal para otro dispositivo. Ahora los clientes pueden ingresar con celular y PIN de seis números. También conservan acceso por enlace personal. No se envían SMS automáticamente.
- Caja busca el código, carga el nuevo comprobante y monto y confirma el canje. Debe aplicar el descuento manualmente en Odoo. No hay integración con Odoo en esta versión.
- Un comprobante genera un giro por modo. Un comprobante nuevo admite un solo cupón del club. No se permite canjear contra la compra que originó el premio.
- Configuración permite ajustar tres descuentos, mínimos, pesos, vigencia y presupuesto nominal diario. Solo nuevos giros usan reglas actualizadas. Los premios existentes conservan monto, mínimo y vencimiento.

## Modo de prueba

Activado por defecto. QR y premios quedan marcados permanentemente como prueba. No se convierten en reales al activar la campaña. La demostración no escribe en Supabase; sus datos solo se guardan en el navegador y no son canjeables.

Valores iniciales ilustrativos: compra mínima $3.000; descuentos $300/$500/$1.000 con mínimos $7.000/$10.000/$15.000 y pesos 60/30/10; vigencia 14 días; presupuesto nominal diario $10.000. Deben revisarse antes de activar premios reales. El presupuesto reserva el valor íntegro del descuento al girar y se reinicia según el día de Chile. Si no alcanza para un premio, se limita el conjunto disponible; cuando no quedan premios, no consume el giro. La apariencia de los sectores no expresa probabilidades.

## Arquitectura

- Frontend estático autocontenido en `dist/index.html`; QR local `dist/vendor/qrcode.js` (qrcode-generator 1.4.4, MIT).
- Supabase project `tmzglobhelevkwerjpom`, conexión Granero. Solo tablas `gf_*`; no se modifica el CRM ni reembolsos.
- Edge Function `granero-club`: validación, aleatoriedad criptográfica, autenticación de caja y acceso mediante enlaces de capacidad.
- PostgreSQL: bloqueo de filas y transacciones para un único giro y canje, restricciones únicas de comprobantes, instantáneas de premios.
- Todas las tablas tienen RLS y se revocó acceso a `anon`/`authenticated`. El frontend no accede a tablas ni funciones directamente. La Edge Function usa la credencial interna de servicio, nunca incluida en navegador o repositorio. Funciones `SECURITY INVOKER`, ejecutables solo por `service_role`.
- Contraseña de caja derivada con PBKDF2-SHA256 (210.000 iteraciones y sal aleatoria); sesiones aleatorias de 256 bits guardadas solo como hash y vencen en 12 h. Límite de intentos por IP. Activación inicial con token aleatorio de un solo uso, solo su hash en la base.
- No hay cuentas de Supabase Auth; el aviso del asesor sobre contraseñas filtradas de Auth no corresponde a este esquema. Avisos informativos de RLS sin políticas reflejan el bloqueo intencional de todo acceso directo.
- La función acepta solicitudes sin JWT de Supabase porque valida sesiones de caja o capacidades de giro/cliente por operación. Solo `config` y `login/setup` tienen acceso inicial; setup exige un secreto de un uso.

## Publicación

La versión en Sites se publica privada para revisión. Los enlaces QR de esa versión también exigen acceso al Site; no distribuirlos a clientes hasta elegir el alojamiento público. El frontend puede alojarse en GitHub Pages sin servidor Node: servir `dist/` y conservar `?giro=…` en la misma ruta. El backend ya reside en Supabase.

En GitHub se conserva bajo `club/` en la rama `club-granero-v1` del repositorio `marcelobarcia/granerfino`; no se reemplaza su portada ni su dominio existente. No publicar el enlace de activación ni accesos personales en el repositorio.

## Verificación

- `scripts/check-club.mjs`: recibe por stdin una sesión temporal de QA; comprueba QR duplicados, giro concurrente idempotente, aislamiento entre accesos, registro, mínimos, compra posterior, canje único y anulación. Crea solo datos `QA-*` en modo prueba, que deben retirarse después.
- Presupuesto verificado con una transacción SQL revertida, sin emitir descuentos reales.
- Recorrido del cliente revisado en navegador. No se han enviado mensajes ni modificado Odoo.

## Alcance operativo

El QR es un enlace portador: quien lo escanea primero puede usar el giro. Caja debe mostrarlo al comprador correcto. El enlace personal debe conservarse como un acceso privado. Las compras y comprobantes se validan manualmente en caja hasta incorporar Odoo. Las sesiones vencidas y registros de intentos deben depurarse en una futura tarea de mantenimiento si aumenta el volumen.
