; =============================================================================
; PROYECTO DE VENTAS E INVENTARIO EN ENSAMBLADOR (UNIDAD 3 - REFACTORIZADO)
; Lenguajes de Interfaz - Arquitectura x86 de 32 bits (MASM + Irvine32)
; Autor: Jose Mario Carrasco Larios
; Negocio elegido: Tienda de Videojuegos y Accesorios "PixelVault Gaming"
; =============================================================================
; Mejoras implementadas en la Version de la Unidad 3:
; 1. PROCEDIMIENTOS REUTILIZABLES: Extraccion de tareas repetidas en:
;    - CapturarYBuscarProducto (unifica captura/validacion/busqueda de codigo).
;    - CapturarCantidadValida  (unifica captura y validacion de cantidades 1..100).
;    - InsertarRegistroEnArreglo (unifica escritura de registros en catalogo y
;      catalogoTemp).
; 2. MACROS CON PARAMETROS Y ETIQUETAS LOCAL:
;    - mImprimir, mImprimirLn, mVerificarRango (con LOCAL), mMostrarEtiquetaEntero,
;      mMostrarEtiquetaImporte y mAgregarCampoArchivo.
; 3. DIRECTIVA USES: Aplicada en los procedimientos para conservar registros
;    automaticamente y mantener equilibrada la pila, dejando fuera de USES los
;    registros que devuelven resultados (como EAX, EBX o ESI segun el caso).
; =============================================================================

INCLUDE Irvine32.inc

; -----------------------------------------------------------------------------
; CONSTANTES SIMBOLICAS DEL SISTEMA Y LAYOUT DE MEMORIA
; -----------------------------------------------------------------------------
MAX_PROD            EQU 10          ; Capacidad maxima: 10 productos
PROD_SIZE           EQU 48          ; Tamano fijo por registro en bytes
OFF_CODIGO          EQU 0           ; Offset 0..7   (8 bytes: "ABC-123" + 00h)
OFF_NOMBRE          EQU 8           ; Offset 8..35  (28 bytes: hasta 25 chars + 00h)
OFF_PRECIO          EQU 36          ; Offset 36..39 (DWORD: precio en centavos)
OFF_EXIST           EQU 40          ; Offset 40..43 (DWORD: existencia 0..100)
OFF_VEND            EQU 44          ; Offset 44..47 (DWORD: unidades vendidas)

MIN_PRECIO_CENT     EQU 1           ; $0.01 MXN = 1 centavo
MAX_PRECIO_CENT     EQU 999999      ; $9999.99 MXN = 999,999 centavos
MAX_EXIST           EQU 100         ; Existencia maxima por producto: 100
MAX_NOMBRE_LEN      EQU 25          ; Longitud maxima del nombre: 25 chars
CODIGO_LEN          EQU 7           ; Longitud exacta del codigo "ABC-123"

UMBRAL_MAYOREO      EQU 5           ; Regla de negocio: >= 5 unidades -> 10% desc.
PORC_DESCUENTO      EQU 10          ; 10% de descuento por mayoreo
STOCK_MINIMO        EQU 5           ; Alerta de existencia minima: <= 5 unidades

FILE_BUF_SIZE       EQU 2048        ; Capacidad del buffer de archivo en bytes
IN_BUF_SIZE         EQU 80          ; Capacidad del buffer de captura ReadString

; =============================================================================
; DEFINICION DE MACROS (UNIDAD 3)
; =============================================================================

; -----------------------------------------------------------------------------
; Macro: mImprimir
; Proposito: Imprime en consola una cadena definida en .data sin salto de linea,
;            conservando el valor original del registro EDX.
; Parametros: cadena = nombre simbolico de la cadena terminada en 00h.
; -----------------------------------------------------------------------------
mImprimir MACRO cadena
    PUSH EDX
    MOV  EDX, OFFSET cadena
    CALL WriteString
    POP  EDX
ENDM

; -----------------------------------------------------------------------------
; Macro: mImprimirLn
; Proposito: Imprime en consola una cadena definida en .data seguida de un
;            salto de linea (Crlf), conservando EDX.
; Parametros: cadena = nombre simbolico de la cadena terminada en 00h.
; -----------------------------------------------------------------------------
mImprimirLn MACRO cadena
    PUSH EDX
    MOV  EDX, OFFSET cadena
    CALL WriteString
    CALL Crlf
    POP  EDX
ENDM

; -----------------------------------------------------------------------------
; Macro: mVerificarRango
; Proposito: Comprueba si un registro o valor sin signo se encuentra dentro del
;            intervalo cerrado [limInf .. limSup]. Si es menor que limInf o
;            mayor que limSup, salta a etqError; en caso contrario continua en
;            la etiqueta interna declarada con LOCAL (EnRango).
; Parametros: regValor = registro a evaluar (ej. AL, EBX, ECX)
;             limInf   = limite inferior permitido
;             limSup   = limite superior permitido
;             etqError = etiqueta de salto en caso de estar fuera de rango
; -----------------------------------------------------------------------------
mVerificarRango MACRO regValor, limInf, limSup, etqError
    LOCAL EnRango
    CMP  regValor, limInf
    JB   etqError
    CMP  regValor, limSup
    JA   etqError
EnRango:
ENDM

; -----------------------------------------------------------------------------
; Macro: mMostrarEtiquetaEntero
; Proposito: Muestra una etiqueta descriptiva, convierte y muestra un valor
;            entero sin signo de 32 bits mediante MostrarEntero, imprime un
;            sufijo textual y termina con salto de linea.
; Parametros: msgEtiqueta = cadena de etiqueta izquierda
;             valor       = registro o variable DWORD a mostrar
;             msgSufijo   = cadena de sufijo (ej. msgUnidades)
; -----------------------------------------------------------------------------
mMostrarEtiquetaEntero MACRO msgEtiqueta, valor, msgSufijo
    PUSH EAX
    mImprimir msgEtiqueta
    MOV  EAX, valor
    CALL MostrarEntero
    mImprimirLn msgSufijo
    POP  EAX
ENDM

; -----------------------------------------------------------------------------
; Macro: mMostrarEtiquetaImporte
; Proposito: Muestra una etiqueta descriptiva seguida de un importe en centavos
;            formateado como "$PESOS.CC MXN" y un salto de linea.
; Parametros: msgEtiqueta   = cadena de etiqueta izquierda
;             valorCentavos = registro o variable DWORD con centavos enteros
; -----------------------------------------------------------------------------
mMostrarEtiquetaImporte MACRO msgEtiqueta, valorCentavos
    PUSH EAX
    mImprimir msgEtiqueta
    MOV  EAX, valorCentavos
    CALL MostrarImporteMXN
    CALL Crlf
    POP  EAX
ENDM

; -----------------------------------------------------------------------------
; Macro: mAgregarCampoArchivo
; Proposito: Empaqueta la copia de una cadena origen hacia el buffer de archivo
;            apuntado por EDI, conservando el puntero de recorrido ESI.
; Parametros: origenStr = expresion de direccion (ej. [ESI + OFF_CODIGO])
; -----------------------------------------------------------------------------
mAgregarCampoArchivo MACRO origenStr
    PUSH ESI
    LEA  ESI, origenStr
    CALL AgregarAlBufferArchivo
    POP  ESI
ENDM

.data
; -----------------------------------------------------------------------------
; ESTRUCTURAS DE DATOS EN MEMORIA (CATALOGO PRINCIPAL Y TEMPORAL)
; -----------------------------------------------------------------------------
catalogo            BYTE (MAX_PROD * PROD_SIZE) DUP(0)
catalogoTemp        BYTE (MAX_PROD * PROD_SIZE) DUP(0)

totalProductos      DWORD 0         ; Cantidad actual de productos en catalogo
totalTemp           DWORD 0         ; Contador temporal durante carga de archivo
ingresosSesion      DWORD 0         ; Ingresos acumulados en centavos (sesion)
descuentosSesion    DWORD 0         ; Descuentos otorgados en centavos (sesion)
cambiosSinGuardar   DWORD 0         ; 0 = sin cambios pendientes, 1 = cambios sin guardar

; Variables de trabajo para operaciones de archivo y validacion temporal
nombreArchivo       BYTE "inventario.txt", 0
manejadorArchivo    DWORD 0
bytesLeidos         DWORD 0
bytesAEscribir      DWORD 0

bufferEntrada       BYTE IN_BUF_SIZE DUP(0)
bufferNumero        BYTE 32 DUP(0)
bufferImporte       BYTE 32 DUP(0)
bufferArchivo       BYTE (FILE_BUF_SIZE + 1) DUP(0)

; Campos temporales para alta y reconstruccion desde archivo
tempCodigo          BYTE 8 DUP(0)
tempNombre          BYTE 28 DUP(0)
tempPrecio          DWORD 0
tempExistencia      DWORD 0
tempCantidad        DWORD 0

; -----------------------------------------------------------------------------
; MENSAJES DE INTERFAZ Y ETIQUETAS DE CONSOLA
; -----------------------------------------------------------------------------
msgBanner1          BYTE "================================================================", 0
msgBanner2          BYTE "   PIXELVAULT GAMING - SISTEMA DE VENTAS E INVENTARIO (U3)      ", 0
msgMenuTitulo       BYTE "--- MENU PRINCIPAL ---", 0
msgMenu1            BYTE "1. Registrar nuevo producto (Alta)", 0
msgMenu2            BYTE "2. Mostrar inventario completo", 0
msgMenu3            BYTE "3. Buscar producto por codigo", 0
msgMenu4            BYTE "4. Recibir mercancia (Entrada de almacen)", 0
msgMenu5            BYTE "5. Realizar venta (Con regla de mayoreo)", 0
msgMenu6            BYTE "6. Mostrar resumen de inventario e ingresos", 0
msgMenu7            BYTE "7. Demostrar regla del negocio y alertas", 0
msgMenu8            BYTE "8. Guardar catalogo en archivo (inventario.txt)", 0
msgMenu9            BYTE "9. Cargar catalogo desde archivo (inventario.txt)", 0
msgMenu0            BYTE "0. Salir del sistema", 0
msgPromptOpcion     BYTE "Seleccione una opcion (0-9): ", 0
msgErrOpcion        BYTE "[!] Opcion invalida. Ingrese un digito del 0 al 9.", 0

; Mensajes de captura y validacion
msgTituloAlta       BYTE "--- 1. REGISTRAR NUEVO PRODUCTO ---", 0
msgPromptCodigo     BYTE "Ingrese codigo (formato ABC-123, 3 mayusculas, guion, 3 digitos): ", 0
msgPromptNombre     BYTE "Ingrese nombre del producto (1 a 25 caracteres, sin '|'): ", 0
msgPromptPrecio     BYTE "Ingrese precio en pesos (0.01 a 9999.99, ej. 185.50): ", 0
msgPromptExistIni   BYTE "Ingrese existencia inicial (entero de 0 a 100): ", 0
msgPromptCantidad   BYTE "Ingrese cantidad de unidades (entero mayor a 0): ", 0

msgErrCapacidad     BYTE "[ERROR] Capacidad maxima alcanzada (10 productos). No se permiten mas altas.", 0
msgErrVacio         BYTE "[ERROR] El dato no puede estar vacio. Intente nuevamente.", 0
msgErrFormatoCod    BYTE "[ERROR] Codigo incorrecto. Debe tener formato exacto ABC-123 (ej. CON-001).", 0
msgErrDuplicado     BYTE "[ERROR] El codigo ya existe en el catalogo. Se rechaza codigo duplicado.", 0
msgErrNombreLen     BYTE "[ERROR] Nombre invalido. Debe tener entre 1 y 25 caracteres sin el caracter '|'.", 0
msgErrPrecio        BYTE "[ERROR] Precio invalido. Use pesos enteros o punto con 1 o 2 decimales (0.01 a 9999.99).", 0
msgErrExistRango    BYTE "[ERROR] Existencia fuera de rango. Debe ser un entero entre 0 y 100.", 0
msgErrCantRango     BYTE "[ERROR] Cantidad invalida. Debe ser un numero entero entre 1 y 100.", 0
msgErrNoEncontrado  BYTE "[ERROR] No se encontro ningun producto con el codigo especificado.", 0
msgErrExcedeMax     BYTE "[ERROR] Operacion rechazada: la nueva existencia superaria el limite de 100 unidades.", 0
msgErrSinStock      BYTE "[ERROR] Venta rechazada: no hay existencias suficientes para cubrir la venta.", 0
msgErrOverflow      BYTE "[ERROR] Operacion rechazada: se detecto desbordamiento aritmetico.", 0

msgExitoAlta        BYTE "[OK] Producto registrado exitosamente en el catalogo.", 0
msgExitoEntrada     BYTE "[OK] Mercancia recibida. Nueva existencia actualizada: ", 0
msgExitoVenta       BYTE "[OK] Venta registrada exitosamente.", 0

; Mensajes de listado y consulta
msgTituloInv        BYTE "--- 2. CATALOGO DE INVENTARIO ACTUAL ---", 0
msgTituloBuscar     BYTE "--- 3. BUSCAR PRODUCTO POR CODIGO ---", 0
msgTituloEntrada    BYTE "--- 4. RECIBIR MERCANCIA (ENTRADA) ---", 0
msgTituloVenta      BYTE "--- 5. REALIZAR VENTA ---", 0
msgTituloResumen    BYTE "--- 6. RESUMEN DE INVENTARIO Y SESION ---", 0
msgTituloRegla      BYTE "--- 7. REGLA DEL NEGOCIO: MAYOREO, STOCK MINIMO Y MAS VENDIDO ---", 0

msgInvVacio         BYTE "El inventario esta vacio actualmente (0 productos registrados).", 0
msgCabeceraTabla    BYTE "CODIGO  | NOMBRE                    | PRECIO UNIT.   | EXIST | VEND | ESTADO", 0
msgSeparadorTabla   BYTE "----------------------------------------------------------------------------", 0
msgColSep           BYTE " | ", 0
msgEspacio          BYTE " ", 0
msgVacioSufijo      BYTE 0
msgEstadoOK         BYTE "OK", 0
msgEstadoBajo       BYTE "ALERTA: STOCK MINIMO (<=5)", 0
msgEstadoAgotado    BYTE "AGOTADO (0)", 0

msgDetalleCod       BYTE "  Codigo     : ", 0
msgDetalleNom       BYTE "  Nombre     : ", 0
msgDetallePre       BYTE "  Precio     : ", 0
msgDetalleExi       BYTE "  Existencia : ", 0
msgDetalleVen       BYTE "  Vendidos   : ", 0
msgUnidades         BYTE " unidades", 0

; Mensajes de desglose de venta
msgVentaSubtotal    BYTE "  Importe base (Precio x Cantidad) : ", 0
msgVentaDescSi      BYTE "  Descuento mayoreo (10% por >=5 u): -", 0
msgVentaDescNo      BYTE "  Descuento mayoreo (<5 unidades)  : $0.00 MXN (No aplica)", 0
msgVentaTotal       BYTE "  IMPORTE FINAL DE LA VENTA        : ", 0
msgVentaExistRest   BYTE "  Existencia restante del producto : ", 0

; Mensajes de resumen y regla de negocio
msgResTotalProd     BYTE "  Productos registrados en catalogo : ", 0
msgResTotalUnid     BYTE "  Unidades totales disponibles      : ", 0
msgResValorInv      BYTE "  Valor total del inventario        : ", 0
msgResIngresos      BYTE "  Ingresos acumulados de la sesion  : ", 0
msgResDescuentos    BYTE "  Ahorro/descuentos otorgados sesion: ", 0
msgReglaExp1        BYTE "  Regla activa 1: 10% de descuento automatico en compras de 5 o mas unidades", 0
msgReglaExp2        BYTE "                  (se descartan fracciones de centavo mediante division entera).", 0
msgReglaExp3        BYTE "  Regla activa 2: Alerta preventiva cuando la existencia es <= 5 unidades.", 0
msgReglaMasVend     BYTE "  Producto mas vendido de la sesion : ", 0
msgSinVentasAun     BYTE "Ninguno (0 ventas realizadas en la sesion)", 0
msgAlertaLista      BYTE "  Productos en alerta de existencia minima (<= 5 unidades):", 0
msgNingunaAlerta    BYTE "  Todos los productos tienen existencia superior al minimo (> 5 unidades).", 0
msgBullet           BYTE "    * ", 0

; Mensajes de archivos y salida
msgTituloGuardar    BYTE "--- 8. GUARDAR CATALOGO EN ARCHIVO ---", 0
msgTituloCargar     BYTE "--- 9. CARGAR CATALOGO DESDE ARCHIVO ---", 0
msgPromptRuta       BYTE "Presione ENTER para usar 'inventario.txt' o escriba otro nombre de archivo: ", 0
msgExitoGuardar     BYTE "[OK] Catalogo guardado correctamente en el archivo. Bytes escritos: ", 0
msgErrCrearArch     BYTE "[ERROR] No se pudo crear el archivo de salida en disco.", 0
msgErrEscribirArch  BYTE "[ERROR] Fallo en WriteToFile: no se escribieron todos los bytes solicitados.", 0
msgExitoCargar      BYTE "[OK] Catalogo validado y cargado exitosamente. Productos recuperados: ", 0
msgErrAbrirArch     BYTE "[ERROR] No se pudo abrir el archivo (archivo ausente o ruta invalida). Se conserva el catalogo actual.", 0
msgErrLeerArch      BYTE "[ERROR] Error de lectura o el archivo excede el tamano permitido.", 0
msgErrArchDanado    BYTE "[ERROR] Archivo danado o con datos invalidos. Se rechaza la carga y se conserva el catalogo anterior.", 0

msgAvisoCambios     BYTE "[AVISO] Hay cambios sin guardar en el catalogo actual.", 0
msgPromptSalir      BYTE "¿Desea salir sin guardar los cambios? (S/N): ", 0
msgDespedida        BYTE "Gracias por utilizar el sistema PixelVault Gaming. ¡Hasta pronto!", 0
msgPausa            BYTE "Presione ENTER para continuar...", 0

; Literales para formateo de importes y archivos
strPrefijoPeso      BYTE "$", 0
strPunto            BYTE ".", 0
strSufijoMXN        BYTE " MXN", 0
strPipe             BYTE "|", 0
strCRLF             BYTE 0Dh, 0Ah, 0

.code
; =============================================================================
; PROCEDIMIENTO PRINCIPAL (main)
; =============================================================================
; Descripcion: Punto de entrada del programa. Muestra el menu interactivo
;              mediante la macro mImprimirLn y despacha cada operacion.
; Entradas:    Ninguna.
; Salidas:     Termina la ejecucion del proceso con ExitProcess.
; Registros modificados: EAX, EDX (nivel superior).
; =============================================================================
main PROC
CicloMenu:
    CALL Crlf
    mImprimirLn msgBanner1
    mImprimirLn msgBanner2
    mImprimirLn msgBanner1
    mImprimirLn msgMenuTitulo
    mImprimirLn msgMenu1
    mImprimirLn msgMenu2
    mImprimirLn msgMenu3
    mImprimirLn msgMenu4
    mImprimirLn msgMenu5
    mImprimirLn msgMenu6
    mImprimirLn msgMenu7
    mImprimirLn msgMenu8
    mImprimirLn msgMenu9
    mImprimirLn msgMenu0
    mImprimir   msgPromptOpcion

    CALL CapturarLinea
    CMP  EAX, 1
    JNE  OpcionInvalida

    MOVZX EAX, BYTE PTR [bufferEntrada]
    CMP  AL, '1'
    JE   IrOpcion1
    CMP  AL, '2'
    JE   IrOpcion2
    CMP  AL, '3'
    JE   IrOpcion3
    CMP  AL, '4'
    JE   IrOpcion4
    CMP  AL, '5'
    JE   IrOpcion5
    CMP  AL, '6'
    JE   IrOpcion6
    CMP  AL, '7'
    JE   IrOpcion7
    CMP  AL, '8'
    JE   IrOpcion8
    CMP  AL, '9'
    JE   IrOpcion9
    CMP  AL, '0'
    JE   IrSalir

OpcionInvalida:
    mImprimirLn msgErrOpcion
    JMP  CicloMenu

IrOpcion1:
    CALL RegistrarProducto
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion2:
    CALL MostrarInventario
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion3:
    CALL ConsultarPorCodigo
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion4:
    CALL RecibirMercancia
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion5:
    CALL VenderProducto
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion6:
    CALL MostrarResumen
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion7:
    CALL MostrarReglaNegocio
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion8:
    CALL GuardarCatalogo
    CALL PausarConsola
    JMP  CicloMenu

IrOpcion9:
    CALL CargarCatalogo
    CALL PausarConsola
    JMP  CicloMenu

IrSalir:
    CALL ConfirmarSalida
    CMP  EAX, 1
    JNE  CicloMenu

    CALL Crlf
    mImprimirLn msgDespedida
    INVOKE ExitProcess, 0
main ENDP

; =============================================================================
; PROCEDIMIENTO: CapturarLinea
; =============================================================================
; Descripcion: Captura una cadena desde el teclado usando ReadString.
;              Aplica USES ECX EDX, dejando EAX fuera de USES porque EAX
;              entrega como resultado la longitud de la cadena capturada.
; Entradas:    Ninguna (usa bufferEntrada global).
; Salidas:     EAX = longitud de la cadena capturada (0 si fue vacia).
;              bufferEntrada = cadena ASCII terminada en nulo (00h).
; Registros modificados: EAX.
; Registros conservados (USES): ECX, EDX.
; =============================================================================
CapturarLinea PROC USES ECX EDX
    MOV  EDX, OFFSET bufferEntrada
    MOV  ECX, IN_BUF_SIZE
    CALL ReadString
    RET
CapturarLinea ENDP

; =============================================================================
; PROCEDIMIENTO: PausarConsola
; =============================================================================
; Descripcion: Muestra un mensaje de pausa y espera ENTER usando ReadString.
; Entradas:    Ninguna.
; Salidas:     Ninguna.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, ECX, EDX.
; =============================================================================
PausarConsola PROC USES EAX ECX EDX
    CALL Crlf
    mImprimir msgPausa
    CALL CapturarLinea
    RET
PausarConsola ENDP

; =============================================================================
; PROCEDIMIENTO: EnteroACadena
; =============================================================================
; Descripcion: Convierte un entero sin signo de 32 bits (EAX) en cadena decimal
;              ASCII terminada en 00h mediante divisiones sucesivas entre 10
;              e inversion de digitos en la pila.
; Entradas:    EAX = numero entero sin signo de 32 bits a convertir.
;              EDI = direccion del buffer destino (al menos 12 bytes).
; Salidas:     Buffer apuntado por EDI con la cadena ASCII + 00h.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, EDI.
; =============================================================================
EnteroACadena PROC USES EAX EBX ECX EDX EDI
    XOR  ECX, ECX
    MOV  EBX, 10

    CMP  EAX, 0
    JNE  CicloDivision
    MOV  BYTE PTR [EDI], '0'
    INC  EDI
    MOV  BYTE PTR [EDI], 0
    JMP  FinEnteroACadena

CicloDivision:
    XOR  EDX, EDX
    DIV  EBX                        ; EAX = cociente, EDX = residuo (0..9)
    ADD  DL, '0'                    ; Convertir digito a ASCII (30h..39h)
    PUSH EDX                        ; Apilar digito para invertir orden
    INC  ECX
    CMP  EAX, 0
    JNE  CicloDivision

CicloExtraccion:
    POP  EDX                        ; Desapilar digitos en orden correcto
    MOV  BYTE PTR [EDI], DL
    INC  EDI
    LOOP CicloExtraccion

    MOV  BYTE PTR [EDI], 0          ; Terminador nulo 00h

FinEnteroACadena:
    RET
EnteroACadena ENDP

; =============================================================================
; PROCEDIMIENTO: MostrarEntero
; =============================================================================
; Descripcion: Convierte el entero en EAX a cadena y lo muestra con WriteString.
; Entradas:    EAX = entero sin signo de 32 bits a mostrar.
; Salidas:     Texto impreso en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EDX, EDI.
; =============================================================================
MostrarEntero PROC USES EDX EDI
    MOV  EDI, OFFSET bufferNumero
    CALL EnteroACadena
    mImprimir bufferNumero
    RET
MostrarEntero ENDP

; =============================================================================
; PROCEDIMIENTO: FormatearCentavosADecimal
; =============================================================================
; Descripcion: Convierte un importe en centavos enteros (EAX) a una cadena
;              con formato "PESOS.CC" separando pesos y centavos con DIV 100.
; Entradas:    EAX = importe total en centavos enteros.
;              EDI = direccion del buffer donde se escribira "PESOS.CC" + 00h.
; Salidas:     Buffer en EDI con cadena terminada en 00h.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
FormatearCentavosADecimal PROC USES EAX EBX ECX EDX ESI EDI
    XOR  EDX, EDX
    MOV  EBX, 100
    DIV  EBX                        ; EAX = pesos, EDX = centavos (0..99)
    MOV  ECX, EDX

    CALL EnteroACadena

AvanzarFinPesos:
    CMP  BYTE PTR [EDI], 0
    JE   ColocarPunto
    INC  EDI
    JMP  AvanzarFinPesos

ColocarPunto:
    MOV  BYTE PTR [EDI], '.'
    INC  EDI

    MOV  EAX, ECX                   ; Formatear residuo de centavos siempre a 2 digitos
    XOR  EDX, EDX
    MOV  EBX, 10
    DIV  EBX                        ; AL = decena de centavo, DL = unidad de centavo
    ADD  AL, '0'
    ADD  DL, '0'
    MOV  BYTE PTR [EDI], AL
    INC  EDI
    MOV  BYTE PTR [EDI], DL
    INC  EDI
    MOV  BYTE PTR [EDI], 0
    RET
FormatearCentavosADecimal ENDP

; =============================================================================
; PROCEDIMIENTO: MostrarImporteMXN
; =============================================================================
; Descripcion: Muestra un importe en centavos enteros (EAX) con el formato
;              "$PESOS.CC MXN" usando WriteString.
; Entradas:    EAX = importe en centavos enteros.
; Salidas:     Texto impreso en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EDX, EDI.
; =============================================================================
MostrarImporteMXN PROC USES EDX EDI
    mImprimir strPrefijoPeso
    MOV  EDI, OFFSET bufferImporte
    CALL FormatearCentavosADecimal
    mImprimir bufferImporte
    mImprimir strSufijoMXN
    RET
MostrarImporteMXN ENDP

; =============================================================================
; PROCEDIMIENTO: ValidarCodigoFormato
; =============================================================================
; Descripcion: Verifica que la cadena en ESI tenga formato "ABC-123" usando
;              la macro mVerificarRango (con etiqueta LOCAL).
;              Deja EAX fuera de USES porque devuelve 1 (valido) o 0 (invalido).
; Entradas:    ESI = direccion de la cadena terminada en 00h.
; Salidas:     EAX = 1 si el formato es valido, 0 si es invalido.
; Registros modificados: EAX.
; Registros conservados (USES): ECX, ESI.
; =============================================================================
ValidarCodigoFormato PROC USES ECX ESI
    MOV  ECX, 3
CicloLetrasCod:
    MOV  AL, BYTE PTR [ESI]
    mVerificarRango AL, 'A', 'Z', CodigoInvalido
    INC  ESI
    LOOP CicloLetrasCod

    CMP  BYTE PTR [ESI], '-'
    JNE  CodigoInvalido
    INC  ESI

    MOV  ECX, 3
CicloDigitosCod:
    MOV  AL, BYTE PTR [ESI]
    mVerificarRango AL, '0', '9', CodigoInvalido
    INC  ESI
    LOOP CicloDigitosCod

    CMP  BYTE PTR [ESI], 0
    JNE  CodigoInvalido

    MOV  EAX, 1
    JMP  FinValidarCodigo

CodigoInvalido:
    XOR  EAX, EAX

FinValidarCodigo:
    RET
ValidarCodigoFormato ENDP

; =============================================================================
; PROCEDIMIENTO: ValidarNombreFormato
; =============================================================================
; Descripcion: Verifica que la cadena en ESI tenga entre 1 y 25 caracteres
;              visibles y no contenga el delimitador '|'.
; Entradas:    ESI = direccion de la cadena de nombre terminada en 00h.
; Salidas:     EAX = 1 si es valido, 0 si es invalido.
; Registros modificados: EAX.
; Registros conservados (USES): ECX, ESI.
; =============================================================================
ValidarNombreFormato PROC USES ECX ESI
    XOR  ECX, ECX
CicloNombreVal:
    MOV  AL, BYTE PTR [ESI]
    CMP  AL, 0
    JE   FinConteoNombre
    CMP  AL, '|'
    JE   NombreInvalido
    CMP  AL, 20h
    JB   NombreInvalido
    INC  ECX
    CMP  ECX, MAX_NOMBRE_LEN
    JA   NombreInvalido
    INC  ESI
    JMP  CicloNombreVal

FinConteoNombre:
    mVerificarRango ECX, 1, MAX_NOMBRE_LEN, NombreInvalido
    MOV  EAX, 1
    JMP  FinValidarNombre

NombreInvalido:
    XOR  EAX, EAX

FinValidarNombre:
    RET
ValidarNombreFormato ENDP

; =============================================================================
; PROCEDIMIENTO: ValidarYConvertirEntero
; =============================================================================
; Descripcion: Convierte una cadena ASCII apuntada por ESI en un entero sin
;              signo de 32 bits en EBX.
;              Deja EAX y EBX fuera de USES porque entregan el estado y el
;              valor convertido respectivamente.
; Entradas:    ESI = direccion de la cadena terminada en 00h.
; Salidas:     EAX = 1 si fue exitoso, 0 si hubo error.
;              EBX = valor entero convertido (si EAX == 1).
; Registros modificados: EAX, EBX.
; Registros conservados (USES): ECX, EDX, ESI.
; =============================================================================
ValidarYConvertirEntero PROC USES ECX EDX ESI
    XOR  EBX, EBX
    XOR  ECX, ECX

    CMP  BYTE PTR [ESI], 0
    JE   EnteroInvalido

CicloDigitosEnt:
    MOVZX EAX, BYTE PTR [ESI]
    CMP  AL, 0
    JE   ExitoEntero

    mVerificarRango AL, '0', '9', EnteroInvalido
    SUB  AL, '0'
    MOV  EDX, EAX

    MOV  EAX, EBX
    MOV  EBX, 10
    PUSH EDX
    MUL  EBX
    POP  EDX
    JC   EnteroInvalido

    ADD  EAX, EDX
    JC   EnteroInvalido
    MOV  EBX, EAX

    INC  ECX
    CMP  ECX, 9
    JA   EnteroInvalido

    INC  ESI
    JMP  CicloDigitosEnt

ExitoEntero:
    MOV  EAX, 1
    JMP  FinValidarEntero

EnteroInvalido:
    XOR  EAX, EAX
    XOR  EBX, EBX

FinValidarEntero:
    RET
ValidarYConvertirEntero ENDP

; =============================================================================
; PROCEDIMIENTO: ValidarYConvertirPrecio
; =============================================================================
; Descripcion: Convierte una cadena de precio en pesos (ej. "185.50", "12.05")
;              a centavos enteros en EBX, rechazando un tercer decimal.
;              Deja EAX y EBX fuera de USES porque entregan los resultados.
; Entradas:    ESI = direccion de la cadena terminada en 00h.
; Salidas:     EAX = 1 si el precio es valido, 0 si es invalido.
;              EBX = precio en centavos enteros (1..999999).
; Registros modificados: EAX, EBX.
; Registros conservados (USES): ECX, EDX, ESI, EDI.
; =============================================================================
ValidarYConvertirPrecio PROC USES ECX EDX ESI EDI
    XOR  EBX, EBX
    XOR  EDI, EDI
    XOR  ECX, ECX
    MOV  EDX, 0

    CMP  BYTE PTR [ESI], 0
    JE   PrecioInvalido

CicloCaracterPrecio:
    MOVZX EAX, BYTE PTR [ESI]
    CMP  AL, 0
    JE   FinalizarCalculoPrecio

    CMP  AL, '.'
    JE   ProcesarPuntoDecimal

    mVerificarRango AL, '0', '9', PrecioInvalido
    SUB  AL, '0'

    CMP  EDX, 0
    JNE  AcumularDecimal

    INC  CL
    IMUL EBX, 10
    ADD  EBX, EAX
    CMP  EBX, 9999
    JA   PrecioInvalido
    INC  ESI
    JMP  CicloCaracterPrecio

ProcesarPuntoDecimal:
    CMP  EDX, 1
    JE   PrecioInvalido
    CMP  CL, 0
    JE   PrecioInvalido
    MOV  EDX, 1
    INC  ESI
    JMP  CicloCaracterPrecio

AcumularDecimal:
    INC  CH
    CMP  CH, 2                      ; Rechazar si hay un tercer decimal (CH > 2)
    JA   PrecioInvalido

    IMUL EDI, 10
    ADD  EDI, EAX
    INC  ESI
    JMP  CicloCaracterPrecio

FinalizarCalculoPrecio:
    CMP  CL, 0
    JE   PrecioInvalido

    CMP  EDX, 1
    JNE  UnirPesosYCentavos
    CMP  CH, 0
    JE   PrecioInvalido

    CMP  CH, 1
    JNE  UnirPesosYCentavos
    IMUL EDI, 10

UnirPesosYCentavos:
    IMUL EBX, 100
    ADD  EBX, EDI

    mVerificarRango EBX, MIN_PRECIO_CENT, MAX_PRECIO_CENT, PrecioInvalido

    MOV  EAX, 1
    JMP  FinValidarPrecio

PrecioInvalido:
    XOR  EAX, EAX
    XOR  EBX, EBX

FinValidarPrecio:
    RET
ValidarYConvertirPrecio ENDP

; =============================================================================
; PROCEDIMIENTO: CompararCodigos
; =============================================================================
; Descripcion: Compara dos cadenas de codigo de 7 caracteres en ESI y EDI.
; Entradas:    ESI = primer codigo, EDI = segundo codigo.
; Salidas:     EAX = 1 si son identicos, 0 si difieren.
; Registros modificados: EAX.
; Registros conservados (USES): ECX, ESI, EDI.
; =============================================================================
CompararCodigos PROC USES ECX ESI EDI
    MOV  ECX, CODIGO_LEN
CicloCompCod:
    MOV  AL, BYTE PTR [ESI]
    CMP  AL, BYTE PTR [EDI]
    JNE  CodigosDistintos
    INC  ESI
    INC  EDI
    LOOP CicloCompCod

    MOV  AL, BYTE PTR [ESI]
    CMP  AL, BYTE PTR [EDI]
    JNE  CodigosDistintos

    MOV  EAX, 1
    JMP  FinCompararCodigos

CodigosDistintos:
    XOR  EAX, EAX

FinCompararCodigos:
    RET
CompararCodigos ENDP

; =============================================================================
; PROCEDIMIENTO: BuscarPorCodigoEnArreglo
; =============================================================================
; Descripcion: Recorre mediante ESI un arreglo de productos buscando el codigo
;              apuntado por EDI.
;              Deja EAX, EBX y ESI fuera de USES porque entregan el resultado
;              de la busqueda (estado, indice y puntero al registro).
; Entradas:    ESI = direccion base del catalogo a recorrer.
;              ECX = numero de productos registrados en ese catalogo.
;              EDI = direccion del codigo buscado.
; Salidas:     EAX = 1 si se encontro, 0 si no existe.
;              ESI = direccion del registro encontrado (si EAX == 1).
;              EBX = indice del producto encontrado (0..9, si EAX == 1).
; Registros modificados: EAX, EBX, ESI.
; Registros conservados (USES): ECX, EDX, EDI.
; =============================================================================
BuscarPorCodigoEnArreglo PROC USES ECX EDX EDI
    XOR  EBX, EBX
    CMP  ECX, 0
    JE   NoEncontradoEnArreglo

CicloBusquedaESI:
    CALL CompararCodigos
    CMP  EAX, 1
    JE   EncontradoEnArreglo

    ADD  ESI, PROD_SIZE
    INC  EBX
    LOOP CicloBusquedaESI

NoEncontradoEnArreglo:
    XOR  EAX, EAX
    XOR  ESI, ESI
    JMP  FinBuscarEnArreglo

EncontradoEnArreglo:
    MOV  EAX, 1

FinBuscarEnArreglo:
    RET
BuscarPorCodigoEnArreglo ENDP

; =============================================================================
; PROCEDIMIENTO: BuscarPorCodigo
; =============================================================================
; Descripcion: Busca el codigo apuntado por EDI dentro del catalogo principal.
; Entradas:    EDI = direccion de la cadena de codigo a buscar.
; Salidas:     EAX = 1 si existe, 0 si no existe; ESI = puntero al producto;
;              EBX = indice (0..9).
; Registros modificados: EAX, EBX, ESI.
; Registros conservados (USES): ECX.
; =============================================================================
BuscarPorCodigo PROC USES ECX
    LEA  ESI, catalogo
    MOV  ECX, totalProductos
    CALL BuscarPorCodigoEnArreglo
    RET
BuscarPorCodigo ENDP

; =============================================================================
; PROCEDIMIENTO: CopiarCadena
; =============================================================================
; Descripcion: Copia una cadena terminada en 00h desde ESI hacia EDI.
; Entradas:    ESI = origen, EDI = destino.
; Salidas:     Cadena copiada incluyendo el byte nulo 00h.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, ESI, EDI.
; =============================================================================
CopiarCadena PROC USES EAX ESI EDI
CicloCopiaStr:
    MOV  AL, BYTE PTR [ESI]
    MOV  BYTE PTR [EDI], AL
    CMP  AL, 0
    JE   FinCopiaStr
    INC  ESI
    INC  EDI
    JMP  CicloCopiaStr

FinCopiaStr:
    RET
CopiarCadena ENDP

; =============================================================================
; PROCEDIMIENTO: MostrarCadenaAlineada
; =============================================================================
; Descripcion: Imprime la cadena en ESI y rellena con espacios hasta ECX chars.
; Entradas:    ESI = direccion de la cadena; ECX = ancho de la columna.
; Salidas:     Texto alineado impreso en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI.
; =============================================================================
MostrarCadenaAlineada PROC USES EAX EBX ECX EDX ESI
    MOV  EDX, ESI
    CALL WriteString

    XOR  EBX, EBX
CicloLenAlin:
    CMP  BYTE PTR [ESI], 0
    JE   RellenarEspacios
    INC  EBX
    INC  ESI
    JMP  CicloLenAlin

RellenarEspacios:
    CMP  EBX, ECX
    JAE  FinCadenaAlineada
    SUB  ECX, EBX
CicloEspacios:
    mImprimir msgEspacio
    LOOP CicloEspacios

FinCadenaAlineada:
    RET
MostrarCadenaAlineada ENDP

; =============================================================================
; PROCEDIMIENTO NUEVO (UNIDAD 3): InsertarRegistroEnArreglo
; =============================================================================
; Descripcion: Procedimiento extraido para eliminar la duplicacion que existia
;              en la Unidad 2 entre RegistrarProducto y CargarCatalogo.
;              Calcula el desplazamiento del registro (indice * PROD_SIZE) a
;              partir de la base en ESI y almacena tempCodigo, tempNombre,
;              tempPrecio, tempExistencia e inicializa OFF_VEND en 0.
; Entradas:    ESI = direccion base del arreglo destino (catalogo o catalogoTemp).
;              EAX = indice del registro donde se insertara (0..9).
;              Variables globales: tempCodigo, tempNombre, tempPrecio, tempExistencia.
; Salidas:     Registro de 48 bytes copiado en la posicion correspondiente.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, ECX, EDX, ESI, EDI.
; =============================================================================
InsertarRegistroEnArreglo PROC USES EAX ECX EDX ESI EDI
    IMUL EAX, PROD_SIZE             ; Desplazamiento = indice * 48 bytes
    ADD  ESI, EAX                   ; ESI apunta al inicio del registro destino

    ; Copiar codigo a [ESI + OFF_CODIGO]
    PUSH ESI
    LEA  EDI, [ESI + OFF_CODIGO]
    LEA  ESI, tempCodigo
    CALL CopiarCadena
    POP  ESI

    ; Copiar nombre a [ESI + OFF_NOMBRE]
    PUSH ESI
    LEA  EDI, [ESI + OFF_NOMBRE]
    LEA  ESI, tempNombre
    CALL CopiarCadena
    POP  ESI

    ; Almacenar precio en centavos, existencia inicial y ventas = 0
    MOV  EAX, tempPrecio
    MOV  DWORD PTR [ESI + OFF_PRECIO], EAX
    MOV  EAX, tempExistencia
    MOV  DWORD PTR [ESI + OFF_EXIST], EAX
    MOV  DWORD PTR [ESI + OFF_VEND], 0
    RET
InsertarRegistroEnArreglo ENDP

; =============================================================================
; PROCEDIMIENTO NUEVO (UNIDAD 3): CapturarYBuscarProducto
; =============================================================================
; Descripcion: Procedimiento reutilizable extraido para eliminar los bloques
;              repetidos de captura, validacion de formato ABC-123 y busqueda
;              de codigo que en la Unidad 2 aparecian triplicados en
;              ConsultarPorCodigo, RecibirMercancia y VenderProducto.
;              Deja EAX y ESI fuera de USES porque entregan el resultado.
; Entradas:    Ninguna (interactivo por consola).
; Salidas:     EAX = 1 si el producto fue localizado exitosamente, 0 si el
;                    inventario esta vacio o el codigo no existe.
;              ESI = direccion del registro del producto en `catalogo` (si EAX==1).
; Registros modificados: EAX, ESI.
; Registros conservados (USES): EBX, EDX, EDI.
; =============================================================================
CapturarYBuscarProducto PROC USES EBX EDX EDI
    CMP  totalProductos, 0
    JNE  CicloPedirCodExistente

    mImprimirLn msgInvVacio
    XOR  EAX, EAX
    XOR  ESI, ESI
    JMP  FinCapturarYBuscar

CicloPedirCodExistente:
    mImprimir msgPromptCodigo
    CALL CapturarLinea
    CMP  EAX, 0
    JE   ErrCodBusqVacio

    LEA  ESI, bufferEntrada
    CALL ValidarCodigoFormato
    CMP  EAX, 1
    JNE  ErrCodBusqFormato

    LEA  EDI, bufferEntrada
    CALL BuscarPorCodigo
    CMP  EAX, 1
    JNE  ErrCodBusqNoExiste

    ; Producto encontrado: EAX = 1 y ESI apunta al registro
    JMP  FinCapturarYBuscar

ErrCodBusqVacio:
    mImprimirLn msgErrVacio
    JMP  CicloPedirCodExistente

ErrCodBusqFormato:
    mImprimirLn msgErrFormatoCod
    JMP  CicloPedirCodExistente

ErrCodBusqNoExiste:
    mImprimirLn msgErrNoEncontrado
    XOR  EAX, EAX
    XOR  ESI, ESI

FinCapturarYBuscar:
    RET
CapturarYBuscarProducto ENDP

; =============================================================================
; PROCEDIMIENTO NUEVO (UNIDAD 3): CapturarCantidadValida
; =============================================================================
; Descripcion: Procedimiento reutilizable extraido para centralizar la captura
;              y validacion de una cantidad entera dentro del rango [1..100],
;              que en la Unidad 2 se repetia en RecibirMercancia y VenderProducto.
;              Deja EBX fuera de USES porque entrega la cantidad validada, y
;              conserva ESI (puntero al producto seleccionado).
; Entradas:    Ninguna (interactivo por consola).
; Salidas:     EBX = cantidad entera validada (entre 1 y 100).
; Registros modificados: EBX.
; Registros conservados (USES): EAX, ECX, EDX, ESI.
; =============================================================================
CapturarCantidadValida PROC USES EAX ECX EDX ESI
CicloPedirCantidad:
    mImprimir msgPromptCantidad
    CALL CapturarLinea
    CMP  EAX, 0
    JE   ErrCantVacia

    LEA  ESI, bufferEntrada
    CALL ValidarYConvertirEntero
    CMP  EAX, 1
    JNE  ErrCantFueraRango

    mVerificarRango EBX, 1, MAX_EXIST, ErrCantFueraRango
    JMP  FinCapturarCantidad

ErrCantVacia:
    mImprimirLn msgErrVacio
    JMP  CicloPedirCantidad

ErrCantFueraRango:
    mImprimirLn msgErrCantRango
    JMP  CicloPedirCantidad

FinCapturarCantidad:
    RET
CapturarCantidadValida ENDP

; =============================================================================
; PROCEDIMIENTO: RegistrarProducto (Funcion Obligatoria 1 - Alta)
; =============================================================================
; Descripcion: Da de alta un nuevo producto en el catalogo verificando
;              capacidad, codigo unico ABC-123, nombre, precio y existencia, y
;              utiliza InsertarRegistroEnArreglo para guardarlo en memoria.
; Entradas:    Ninguna (interactivo).
; Salidas:     Nuevo registro en `catalogo`, incrementa `totalProductos`.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
RegistrarProducto PROC USES EAX EBX ECX EDX ESI EDI
    CALL Crlf
    mImprimirLn msgTituloAlta

    MOV  EAX, totalProductos
    CMP  EAX, MAX_PROD
    JB   CapturarNuevoCodigo

    mImprimirLn msgErrCapacidad
    JMP  FinRegistrarProducto

CapturarNuevoCodigo:
    mImprimir msgPromptCodigo
    CALL CapturarLinea
    CMP  EAX, 0
    JE   ErrorCodigoVacio

    LEA  ESI, bufferEntrada
    CALL ValidarCodigoFormato
    CMP  EAX, 1
    JNE  ErrorCodigoFormato

    LEA  EDI, bufferEntrada
    CALL BuscarPorCodigo
    CMP  EAX, 1
    JE   ErrorCodigoDuplicado

    LEA  ESI, bufferEntrada
    LEA  EDI, tempCodigo
    CALL CopiarCadena
    JMP  CapturarNuevoNombre

ErrorCodigoVacio:
    mImprimirLn msgErrVacio
    JMP  CapturarNuevoCodigo

ErrorCodigoFormato:
    mImprimirLn msgErrFormatoCod
    JMP  CapturarNuevoCodigo

ErrorCodigoDuplicado:
    mImprimirLn msgErrDuplicado
    JMP  CapturarNuevoCodigo

CapturarNuevoNombre:
    mImprimir msgPromptNombre
    CALL CapturarLinea
    CMP  EAX, 0
    JE   ErrorNombreVacio

    LEA  ESI, bufferEntrada
    CALL ValidarNombreFormato
    CMP  EAX, 1
    JNE  ErrorNombreInvalido

    LEA  ESI, bufferEntrada
    LEA  EDI, tempNombre
    CALL CopiarCadena
    JMP  CapturarNuevoPrecio

ErrorNombreVacio:
    mImprimirLn msgErrVacio
    JMP  CapturarNuevoNombre

ErrorNombreInvalido:
    mImprimirLn msgErrNombreLen
    JMP  CapturarNuevoNombre

CapturarNuevoPrecio:
    mImprimir msgPromptPrecio
    CALL CapturarLinea
    CMP  EAX, 0
    JE   ErrorPrecioVacio

    LEA  ESI, bufferEntrada
    CALL ValidarYConvertirPrecio
    CMP  EAX, 1
    JNE  ErrorPrecioFormato

    MOV  tempPrecio, EBX
    JMP  CapturarNuevaExistencia

ErrorPrecioVacio:
    mImprimirLn msgErrVacio
    JMP  CapturarNuevoPrecio

ErrorPrecioFormato:
    mImprimirLn msgErrPrecio
    JMP  CapturarNuevoPrecio

CapturarNuevaExistencia:
    mImprimir msgPromptExistIni
    CALL CapturarLinea
    CMP  EAX, 0
    JE   ErrorExistVacia

    LEA  ESI, bufferEntrada
    CALL ValidarYConvertirEntero
    CMP  EAX, 1
    JNE  ErrorExistRango
    CMP  EBX, MAX_EXIST
    JA   ErrorExistRango

    MOV  tempExistencia, EBX

    ; Insertar en `catalogo` usando el procedimiento reutilizable (Unidad 3)
    LEA  ESI, catalogo
    MOV  EAX, totalProductos
    CALL InsertarRegistroEnArreglo

    INC  totalProductos
    MOV  cambiosSinGuardar, 1

    CALL Crlf
    mImprimirLn msgExitoAlta
    JMP  FinRegistrarProducto

ErrorExistVacia:
    mImprimirLn msgErrVacio
    JMP  CapturarNuevaExistencia

ErrorExistRango:
    mImprimirLn msgErrExistRango
    JMP  CapturarNuevaExistencia

FinRegistrarProducto:
    RET
RegistrarProducto ENDP

; =============================================================================
; PROCEDIMIENTO: MostrarInventario (Funcion Obligatoria 1 - Mostrar)
; =============================================================================
; Descripcion: Recorre `catalogo` con ESI y muestra la tabla de productos.
; Entradas:    Ninguna.
; Salidas:     Tabla impresa en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
MostrarInventario PROC USES EAX EBX ECX EDX ESI EDI
    CALL Crlf
    mImprimirLn msgTituloInv

    MOV  ECX, totalProductos
    CMP  ECX, 0
    JNE  ImprimirCabeceraInv

    mImprimirLn msgInvVacio
    JMP  FinMostrarInventario

ImprimirCabeceraInv:
    mImprimirLn msgCabeceraTabla
    mImprimirLn msgSeparadorTabla

    LEA  ESI, catalogo

CicloImprimirProd:
    MOV  EDX, ESI
    CALL WriteString
    mImprimir msgColSep

    PUSH ECX
    PUSH ESI
    LEA  ESI, [ESI + OFF_NOMBRE]
    MOV  ECX, 25
    CALL MostrarCadenaAlineada
    POP  ESI
    POP  ECX

    mImprimir msgColSep

    MOV  EAX, DWORD PTR [ESI + OFF_PRECIO]
    CALL MostrarImporteMXN
    mImprimir msgColSep

    MOV  EAX, DWORD PTR [ESI + OFF_EXIST]
    CALL MostrarEntero
    mImprimir msgColSep

    MOV  EAX, DWORD PTR [ESI + OFF_VEND]
    CALL MostrarEntero
    mImprimir msgColSep

    MOV  EAX, DWORD PTR [ESI + OFF_EXIST]
    CMP  EAX, 0
    JE   EstadoProdAgotado
    CMP  EAX, STOCK_MINIMO
    JBE  EstadoProdBajo

    mImprimirLn msgEstadoOK
    JMP  SiguienteProdInv

EstadoProdAgotado:
    mImprimirLn msgEstadoAgotado
    JMP  SiguienteProdInv

EstadoProdBajo:
    mImprimirLn msgEstadoBajo

SiguienteProdInv:
    ADD  ESI, PROD_SIZE
    DEC  ECX
    JNZ  CicloImprimirProd

    mImprimirLn msgSeparadorTabla

FinMostrarInventario:
    RET
MostrarInventario ENDP

; =============================================================================
; PROCEDIMIENTO: MostrarDetalleProducto
; =============================================================================
; Descripcion: Muestra los campos del producto apuntado por ESI apoyandose en
;              las macros mImprimir, mMostrarEtiquetaImporte y mMostrarEtiquetaEntero.
; Entradas:    ESI = puntero al registro del producto en `catalogo`.
; Salidas:     Ficha impresa en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EDX, ESI.
; =============================================================================
MostrarDetalleProducto PROC USES EAX EDX ESI
    mImprimir msgDetalleCod
    LEA  EDX, [ESI + OFF_CODIGO]
    CALL WriteString
    CALL Crlf

    mImprimir msgDetalleNom
    LEA  EDX, [ESI + OFF_NOMBRE]
    CALL WriteString
    CALL Crlf

    mMostrarEtiquetaImporte msgDetallePre, DWORD PTR [ESI + OFF_PRECIO]
    mMostrarEtiquetaEntero  msgDetalleExi, DWORD PTR [ESI + OFF_EXIST], msgUnidades
    mMostrarEtiquetaEntero  msgDetalleVen, DWORD PTR [ESI + OFF_VEND], msgUnidades
    RET
MostrarDetalleProducto ENDP

; =============================================================================
; PROCEDIMIENTO: ConsultarPorCodigo (Funcion Obligatoria 1 - Buscar)
; =============================================================================
; Descripcion: Localiza un producto reutilizando CapturarYBuscarProducto y
;              muestra su detalle.
; Entradas:    Ninguna (interactivo).
; Salidas:     Detalle del producto en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, ESI.
; =============================================================================
ConsultarPorCodigo PROC USES EAX ESI
    CALL Crlf
    mImprimirLn msgTituloBuscar

    CALL CapturarYBuscarProducto
    CMP  EAX, 1
    JNE  FinConsultarCodigo

    CALL Crlf
    CALL MostrarDetalleProducto

FinConsultarCodigo:
    RET
ConsultarPorCodigo ENDP

; =============================================================================
; PROCEDIMIENTO: RecibirMercancia (Funcion Obligatoria 2 - Entrada de almacen)
; =============================================================================
; Descripcion: Reutiliza CapturarYBuscarProducto y CapturarCantidadValida para
;              sumar unidades a un producto existente sin exceder 100 unidades.
; Entradas:    Ninguna (interactivo).
; Salidas:     Existencia actualizada en [ESI + OFF_EXIST] y cambiosSinGuardar=1.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, EDX, ESI.
; =============================================================================
RecibirMercancia PROC USES EAX EBX EDX ESI
    CALL Crlf
    mImprimirLn msgTituloEntrada

    CALL CapturarYBuscarProducto
    CMP  EAX, 1
    JNE  FinRecibirMercancia

    CALL Crlf
    CALL MostrarDetalleProducto
    CALL Crlf

PedirCantEntrada:
    CALL CapturarCantidadValida     ; Devuelve en EBX una cantidad entera en [1..100]

    MOV  EAX, DWORD PTR [ESI + OFF_EXIST]
    ADD  EAX, EBX
    JC   ErrCantEntExcede
    CMP  EAX, MAX_EXIST
    JA   ErrCantEntExcede

    MOV  DWORD PTR [ESI + OFF_EXIST], EAX
    MOV  cambiosSinGuardar, 1

    CALL Crlf
    mMostrarEtiquetaEntero msgExitoEntrada, EAX, msgUnidades
    JMP  FinRecibirMercancia

ErrCantEntExcede:
    mImprimirLn msgErrExcedeMax
    JMP  PedirCantEntrada

FinRecibirMercancia:
    RET
RecibirMercancia ENDP

; =============================================================================
; PROCEDIMIENTO: VenderProducto (Funcion Obligatoria 3 y Regla de Negocio 6)
; =============================================================================
; Descripcion: Reutiliza CapturarYBuscarProducto y CapturarCantidadValida para
;              realizar una venta comprobando existencias, aplicando el 10% de
;              descuento por mayoreo (>= 5 unidades) y verificando overflow.
; Entradas:    Ninguna (interactivo).
; Salidas:     Actualiza existencias, ventas e ingresos de la sesion.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
VenderProducto PROC USES EAX EBX ECX EDX ESI EDI
    CALL Crlf
    mImprimirLn msgTituloVenta

    CALL CapturarYBuscarProducto
    CMP  EAX, 1
    JNE  FinVenderProducto

    CALL Crlf
    CALL MostrarDetalleProducto
    CALL Crlf

    CMP  DWORD PTR [ESI + OFF_EXIST], 0
    JE   ErrVenSinStockSalir

PedirCantVenta:
    CALL CapturarCantidadValida     ; Devuelve en EBX cantidad validada (1..100)

    MOV  ECX, DWORD PTR [ESI + OFF_EXIST]
    CMP  EBX, ECX
    JA   ErrCantVenSinStock

    MOV  tempCantidad, EBX

    ; Calcular importe base = precio * cantidad y comprobar desbordamiento
    MOV  EAX, DWORD PTR [ESI + OFF_PRECIO]
    MUL  EBX
    JC   ErrVenOverflow
    MOV  ECX, EAX                   ; ECX = importeBase en centavos

    ; Regla del Negocio: 10% de descuento si tempCantidad >= 5
    XOR  EDI, EDI
    CMP  tempCantidad, UMBRAL_MAYOREO
    JB   CalcularImporteFinal

    MOV  EAX, ECX
    XOR  EDX, EDX
    MOV  EBX, 10
    DIV  EBX                        ; EAX = 10% en centavos enteros, EDX = fraccion descartada
    MOV  EDI, EAX

CalcularImporteFinal:
    MOV  EAX, ECX
    SUB  EAX, EDI                   ; EAX = importeFinal

    MOV  EBX, ingresosSesion
    ADD  EBX, EAX
    JC   ErrVenOverflow

    MOV  EDX, descuentosSesion
    ADD  EDX, EDI
    JC   ErrVenOverflow

    ; Comprometer cambios en memoria de forma atomica
    MOV  ingresosSesion, EBX
    MOV  descuentosSesion, EDX

    MOV  EBX, tempCantidad
    SUB  DWORD PTR [ESI + OFF_EXIST], EBX
    ADD  DWORD PTR [ESI + OFF_VEND], EBX
    MOV  cambiosSinGuardar, 1

    ; Mostrar desglose con macros
    CALL Crlf
    mImprimirLn msgExitoVenta
    mMostrarEtiquetaImporte msgVentaSubtotal, ECX

    CMP  EDI, 0
    JE   MostrarSinDescuento

    mMostrarEtiquetaImporte msgVentaDescSi, EDI
    JMP  MostrarTotalVenta

MostrarSinDescuento:
    mImprimirLn msgVentaDescNo

MostrarTotalVenta:
    mMostrarEtiquetaImporte msgVentaTotal, EAX
    mMostrarEtiquetaEntero  msgVentaExistRest, DWORD PTR [ESI + OFF_EXIST], msgUnidades
    JMP  FinVenderProducto

ErrVenSinStockSalir:
    mImprimirLn msgErrSinStock
    JMP  FinVenderProducto

ErrCantVenSinStock:
    mImprimirLn msgErrSinStock
    JMP  PedirCantVenta

ErrVenOverflow:
    mImprimirLn msgErrOverflow

FinVenderProducto:
    RET
VenderProducto ENDP

; =============================================================================
; PROCEDIMIENTO: MostrarResumen (Funcion Obligatoria 4 - Resumen)
; =============================================================================
; Descripcion: Recorre el catalogo con ESI para presentar unidades disponibles,
;              valor total del inventario e ingresos acumulados de la sesion.
; Entradas:    Ninguna.
; Salidas:     Resumen impreso en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
MostrarResumen PROC USES EAX EBX ECX EDX ESI EDI
    CALL Crlf
    mImprimirLn msgTituloResumen

    XOR  EBX, EBX
    XOR  EDI, EDI
    MOV  ECX, totalProductos
    CMP  ECX, 0
    JE   ImprimirDatosResumen

    LEA  ESI, catalogo

CicloCalculoResumen:
    MOV  EAX, DWORD PTR [ESI + OFF_EXIST]
    ADD  EBX, EAX

    MOV  EDX, DWORD PTR [ESI + OFF_PRECIO]
    IMUL EAX, EDX
    ADD  EDI, EAX

    ADD  ESI, PROD_SIZE
    LOOP CicloCalculoResumen

ImprimirDatosResumen:
    mMostrarEtiquetaEntero  msgResTotalProd,  totalProductos,   msgVacioSufijo
    mMostrarEtiquetaEntero  msgResTotalUnid,  EBX,              msgUnidades
    mMostrarEtiquetaImporte msgResValorInv,   EDI
    mMostrarEtiquetaImporte msgResIngresos,   ingresosSesion
    mMostrarEtiquetaImporte msgResDescuentos, descuentosSesion
    RET
MostrarResumen ENDP

; =============================================================================
; PROCEDIMIENTO: MostrarReglaNegocio (Funcion Obligatoria 6 - Regla del Negocio)
; =============================================================================
; Descripcion: Presenta la regla del negocio, el producto mas vendido y las
;              alertas de existencia minima (<= 5 unidades) recorriendo con ESI.
; Entradas:    Ninguna.
; Salidas:     Reporte de regla del negocio impreso en consola.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
MostrarReglaNegocio PROC USES EAX EBX ECX EDX ESI EDI
    CALL Crlf
    mImprimirLn msgTituloRegla
    mImprimirLn msgReglaExp1
    mImprimirLn msgReglaExp2
    mImprimirLn msgReglaExp3
    CALL Crlf

    MOV  ECX, totalProductos
    CMP  ECX, 0
    JNE  BuscarMasVendido

    mImprimirLn msgInvVacio
    JMP  FinMostrarRegla

BuscarMasVendido:
    LEA  ESI, catalogo
    XOR  EBX, EBX
    XOR  EDI, EDI

CicloMasVendido:
    MOV  EAX, DWORD PTR [ESI + OFF_VEND]
    CMP  EAX, EBX
    JBE  SiguienteMasVendido
    MOV  EBX, EAX
    MOV  EDI, ESI

SiguienteMasVendido:
    ADD  ESI, PROD_SIZE
    LOOP CicloMasVendido

    mImprimir msgReglaMasVend
    CMP  EBX, 0
    JE   NingunVendido

    LEA  EDX, [EDI + OFF_CODIGO]
    CALL WriteString
    mImprimir msgColSep
    LEA  EDX, [EDI + OFF_NOMBRE]
    CALL WriteString
    mMostrarEtiquetaEntero msgColSep, EBX, msgUnidades
    JMP  ListarAlertasStock

NingunVendido:
    mImprimirLn msgSinVentasAun

ListarAlertasStock:
    CALL Crlf
    mImprimirLn msgAlertaLista

    LEA  ESI, catalogo
    MOV  ECX, totalProductos
    XOR  EBX, EBX

CicloAlertasESI:
    MOV  EAX, DWORD PTR [ESI + OFF_EXIST]
    CMP  EAX, STOCK_MINIMO
    JA   SiguienteAlerta

    INC  EBX
    mImprimir msgBullet
    LEA  EDX, [ESI + OFF_CODIGO]
    CALL WriteString
    mImprimir msgColSep
    LEA  EDX, [ESI + OFF_NOMBRE]
    CALL WriteString
    mMostrarEtiquetaEntero msgColSep, DWORD PTR [ESI + OFF_EXIST], msgUnidades

SiguienteAlerta:
    ADD  ESI, PROD_SIZE
    LOOP CicloAlertasESI

    CMP  EBX, 0
    JNE  FinMostrarRegla
    mImprimirLn msgNingunaAlerta

FinMostrarRegla:
    RET
MostrarReglaNegocio ENDP

; =============================================================================
; PROCEDIMIENTO: AgregarAlBufferArchivo
; =============================================================================
; Descripcion: Copia la cadena en ESI al final del buffer apuntado por EDI.
;              Deja EDI fuera de USES porque devuelve el puntero avanzado.
; Entradas:    ESI = cadena origen; EDI = posicion actual en bufferArchivo.
; Salidas:     EDI actualizado; bytesAEscribir incrementado.
; Registros modificados: EDI.
; Registros conservados (USES): EAX, ESI.
; =============================================================================
AgregarAlBufferArchivo PROC USES EAX ESI
CicloAgregarBuf:
    MOV  AL, BYTE PTR [ESI]
    CMP  AL, 0
    JE   FinAgregarBuf
    MOV  BYTE PTR [EDI], AL
    INC  EDI
    INC  ESI
    INC  bytesAEscribir
    JMP  CicloAgregarBuf

FinAgregarBuf:
    RET
AgregarAlBufferArchivo ENDP

; =============================================================================
; PROCEDIMIENTO: SeleccionarNombreArchivo
; =============================================================================
; Descripcion: Permite elegir ENTER para "inventario.txt" u escribir otra ruta.
;              Deja EDX fuera de USES porque devuelve el offset de la ruta.
; Entradas:    Ninguna.
; Salidas:     EDX = direccion de la cadena con el nombre del archivo.
; Registros modificados: EDX.
; Registros conservados (USES): EAX.
; =============================================================================
SeleccionarNombreArchivo PROC USES EAX
    mImprimir msgPromptRuta
    CALL CapturarLinea
    CMP  EAX, 0
    JE   UsarRutaPorDefecto

    MOV  EDX, OFFSET bufferEntrada
    JMP  FinSeleccionarRuta

UsarRutaPorDefecto:
    MOV  EDX, OFFSET nombreArchivo

FinSeleccionarRuta:
    RET
SeleccionarNombreArchivo ENDP

; =============================================================================
; PROCEDIMIENTO: GuardarCatalogo (Funcion Obligatoria 5 - Guardar)
; =============================================================================
; Descripcion: Serializa el catalogo apoyandose en la macro mAgregarCampoArchivo
;              y escribe en disco verificando que EAX == bytesAEscribir.
; Entradas:    Ninguna.
; Salidas:     Archivo escrito en disco y cambiosSinGuardar = 0.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
GuardarCatalogo PROC USES EAX EBX ECX EDX ESI EDI
    CALL Crlf
    mImprimirLn msgTituloGuardar

    MOV  bytesAEscribir, 0
    LEA  EDI, bufferArchivo
    LEA  ESI, catalogo
    MOV  ECX, totalProductos
    CMP  ECX, 0
    JE   AbrirArchivoSalida

CicloSerializarProd:
    mAgregarCampoArchivo [ESI + OFF_CODIGO]
    mAgregarCampoArchivo strPipe
    mAgregarCampoArchivo [ESI + OFF_NOMBRE]
    mAgregarCampoArchivo strPipe

    MOV  EAX, DWORD PTR [ESI + OFF_PRECIO]
    PUSH EDI
    LEA  EDI, bufferImporte
    CALL FormatearCentavosADecimal
    POP  EDI
    mAgregarCampoArchivo bufferImporte
    mAgregarCampoArchivo strPipe

    MOV  EAX, DWORD PTR [ESI + OFF_EXIST]
    PUSH EDI
    LEA  EDI, bufferNumero
    CALL EnteroACadena
    POP  EDI
    mAgregarCampoArchivo bufferNumero
    mAgregarCampoArchivo strCRLF

    ADD  ESI, PROD_SIZE
    LOOP CicloSerializarProd

AbrirArchivoSalida:
    CALL SeleccionarNombreArchivo
    CALL CreateOutputFile
    CMP  EAX, INVALID_HANDLE_VALUE
    JE   ErrorCrearArchivo
    MOV  manejadorArchivo, EAX

    CMP  bytesAEscribir, 0
    JE   CerrarArchivoGuardado

    MOV  EAX, manejadorArchivo
    MOV  EDX, OFFSET bufferArchivo
    MOV  ECX, bytesAEscribir
    CALL WriteToFile

    PUSH EAX
    MOV  EAX, manejadorArchivo
    CALL CloseFile
    POP  EAX

    CMP  EAX, bytesAEscribir
    JNE  ErrorEscrituraIncompleta

    MOV  cambiosSinGuardar, 0
    mMostrarEtiquetaEntero msgExitoGuardar, EAX, msgVacioSufijo
    JMP  FinGuardarCatalogo

CerrarArchivoGuardado:
    MOV  EAX, manejadorArchivo
    CALL CloseFile
    MOV  cambiosSinGuardar, 0
    mMostrarEtiquetaEntero msgExitoGuardar, 0, msgVacioSufijo
    JMP  FinGuardarCatalogo

ErrorCrearArchivo:
    mImprimirLn msgErrCrearArch
    JMP  FinGuardarCatalogo

ErrorEscrituraIncompleta:
    mImprimirLn msgErrEscribirArch

FinGuardarCatalogo:
    RET
GuardarCatalogo ENDP

; =============================================================================
; PROCEDIMIENTO: ExtraerCampoArchivo
; =============================================================================
; Descripcion: Extrae un campo desde bufferArchivo (ESI) hasta el delimitador BL.
;              Deja EAX y ESI fuera de USES porque entregan el estado y el
;              puntero de lectura avanzado.
; Entradas:    ESI = lectura en bufferArchivo; EDI = destino; ECX = max len;
;              BL = delimitador ('|' o 0Ah).
; Salidas:     EAX = 1 si fue valido, 0 si hubo error; ESI avanzado.
; Registros modificados: EAX, ESI.
; Registros conservados (USES): EBX, ECX, EDX, EDI.
; =============================================================================
ExtraerCampoArchivo PROC USES EBX ECX EDX EDI
    XOR  EDX, EDX

CicloExtraerCampo:
    MOV  AL, BYTE PTR [ESI]

    CMP  BL, '|'
    JNE  VerificarFinLinea

    CMP  AL, '|'
    JE   DelimitadorPipeEncontrado
    CMP  AL, 0
    JE   ErrorCampoArchivo
    CMP  AL, 0Dh
    JE   ErrorCampoArchivo
    CMP  AL, 0Ah
    JE   ErrorCampoArchivo
    JMP  CopiarCaracterCampo

VerificarFinLinea:
    CMP  AL, 0Dh
    JE   DelimitadorCR
    CMP  AL, 0Ah
    JE   DelimitadorLF
    CMP  AL, 0
    JE   DelimitadorNulo
    CMP  AL, '|'
    JE   ErrorCampoArchivo

CopiarCaracterCampo:
    INC  EDX
    CMP  EDX, ECX
    JA   ErrorCampoArchivo
    MOV  BYTE PTR [EDI], AL
    INC  EDI
    INC  ESI
    JMP  CicloExtraerCampo

DelimitadorPipeEncontrado:
    INC  ESI
    JMP  CerrarCampoExtraido

DelimitadorCR:
    INC  ESI
    CMP  BYTE PTR [ESI], 0Ah
    JNE  CerrarCampoExtraido
    INC  ESI
    JMP  CerrarCampoExtraido

DelimitadorLF:
    INC  ESI
    JMP  CerrarCampoExtraido

DelimitadorNulo:
    JMP  CerrarCampoExtraido

CerrarCampoExtraido:
    CMP  EDX, 0
    JE   ErrorCampoArchivo
    MOV  BYTE PTR [EDI], 0
    MOV  EAX, 1
    JMP  FinExtraerCampo

ErrorCampoArchivo:
    XOR  EAX, EAX

FinExtraerCampo:
    RET
ExtraerCampoArchivo ENDP

; =============================================================================
; PROCEDIMIENTO: CargarCatalogo (Funcion Obligatoria 5 - Cargar y Validar)
; =============================================================================
; Descripcion: Lee el archivo en bufferArchivo, agrega 00h en [bufferArchivo+EAX],
;              valida todos los campos e inserta en catalogoTemp reutilizando
;              InsertarRegistroEnArreglo. Si todo el archivo es valido,
;              reemplaza `catalogo`.
; Entradas:    Ninguna (interactivo).
; Salidas:     `catalogo` y `totalProductos` actualizados si el archivo es valido.
; Registros modificados: Ninguno.
; Registros conservados (USES): EAX, EBX, ECX, EDX, ESI, EDI.
; =============================================================================
CargarCatalogo PROC USES EAX EBX ECX EDX ESI EDI
    CALL Crlf
    mImprimirLn msgTituloCargar

    CALL SeleccionarNombreArchivo
    CALL OpenInputFile
    CMP  EAX, INVALID_HANDLE_VALUE
    JE   ErrorAbrirArchivoEntrada
    MOV  manejadorArchivo, EAX

    MOV  EAX, manejadorArchivo
    MOV  EDX, OFFSET bufferArchivo
    MOV  ECX, FILE_BUF_SIZE
    CALL ReadFromFile
    JC   ErrorLecturaArchivo

    MOV  bytesLeidos, EAX
    MOV  EAX, manejadorArchivo
    CALL CloseFile

    MOV  EAX, bytesLeidos
    MOV  BYTE PTR [bufferArchivo + EAX], 0

    MOV  totalTemp, 0
    LEA  ESI, bufferArchivo

CicloLineasArchivo:
SaltarLineasVacias:
    MOV  AL, BYTE PTR [ESI]
    CMP  AL, 0
    JE   FinParseoExitoso
    CMP  AL, 0Dh
    JE   AvanzarCharBlanco
    CMP  AL, 0Ah
    JE   AvanzarCharBlanco
    JMP  ProcesarLineaProducto

AvanzarCharBlanco:
    INC  ESI
    JMP  SaltarLineasVacias

ProcesarLineaProducto:
    MOV  EAX, totalTemp
    CMP  EAX, MAX_PROD
    JAE  ErrorArchivoCorrupto

    ; Campo 1: CODIGO
    LEA  EDI, tempCodigo
    MOV  ECX, CODIGO_LEN
    MOV  BL, '|'
    CALL ExtraerCampoArchivo
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto

    PUSH ESI
    LEA  ESI, tempCodigo
    CALL ValidarCodigoFormato
    POP  ESI
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto

    PUSH ESI
    LEA  ESI, catalogoTemp
    MOV  ECX, totalTemp
    LEA  EDI, tempCodigo
    CALL BuscarPorCodigoEnArreglo
    POP  ESI
    CMP  EAX, 1
    JE   ErrorArchivoCorrupto

    ; Campo 2: NOMBRE
    LEA  EDI, tempNombre
    MOV  ECX, MAX_NOMBRE_LEN
    MOV  BL, '|'
    CALL ExtraerCampoArchivo
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto

    PUSH ESI
    LEA  ESI, tempNombre
    CALL ValidarNombreFormato
    POP  ESI
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto

    ; Campo 3: PRECIO
    LEA  EDI, bufferImporte
    MOV  ECX, 12
    MOV  BL, '|'
    CALL ExtraerCampoArchivo
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto

    PUSH ESI
    LEA  ESI, bufferImporte
    CALL ValidarYConvertirPrecio
    POP  ESI
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto
    MOV  tempPrecio, EBX

    ; Campo 4: EXISTENCIA
    LEA  EDI, bufferNumero
    MOV  ECX, 6
    MOV  BL, 0Ah
    CALL ExtraerCampoArchivo
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto

    PUSH ESI
    LEA  ESI, bufferNumero
    CALL ValidarYConvertirEntero
    POP  ESI
    CMP  EAX, 1
    JNE  ErrorArchivoCorrupto
    CMP  EBX, MAX_EXIST
    JA   ErrorArchivoCorrupto
    MOV  tempExistencia, EBX

    ; Reutilizar InsertarRegistroEnArreglo sobre catalogoTemp (Unidad 3)
    PUSH ESI
    LEA  ESI, catalogoTemp
    MOV  EAX, totalTemp
    CALL InsertarRegistroEnArreglo
    POP  ESI

    INC  totalTemp
    JMP  CicloLineasArchivo

FinParseoExitoso:
    CMP  totalTemp, 0
    JE   ErrorArchivoCorrupto

    LEA  ESI, catalogoTemp
    LEA  EDI, catalogo
    MOV  ECX, (MAX_PROD * PROD_SIZE)
CicloReemplazarCatalogo:
    MOV  AL, BYTE PTR [ESI]
    MOV  BYTE PTR [EDI], AL
    INC  ESI
    INC  EDI
    LOOP CicloReemplazarCatalogo

    MOV  EAX, totalTemp
    MOV  totalProductos, EAX
    MOV  cambiosSinGuardar, 0

    mMostrarEtiquetaEntero msgExitoCargar, EAX, msgVacioSufijo
    JMP  FinCargarCatalogo

ErrorAbrirArchivoEntrada:
    mImprimirLn msgErrAbrirArch
    JMP  FinCargarCatalogo

ErrorLecturaArchivo:
    MOV  EAX, manejadorArchivo
    CALL CloseFile
    mImprimirLn msgErrLeerArch
    JMP  FinCargarCatalogo

ErrorArchivoCorrupto:
    mImprimirLn msgErrArchDanado

FinCargarCatalogo:
    RET
CargarCatalogo ENDP

; =============================================================================
; PROCEDIMIENTO: ConfirmarSalida (Funcion Obligatoria 5 - Avisar al salir)
; =============================================================================
; Descripcion: Si cambiosSinGuardar == 1, pide confirmacion antes de salir.
;              Deja EAX fuera de USES porque devuelve 1 (salir) o 0 (cancelar).
; Entradas:    Ninguna.
; Salidas:     EAX = 1 si confirma salida, 0 si regresa al menu.
; Registros modificados: EAX.
; Registros conservados (USES): EDX.
; =============================================================================
ConfirmarSalida PROC USES EDX
    CMP  cambiosSinGuardar, 0
    JE   PermitirSalida

    CALL Crlf
    mImprimirLn msgAvisoCambios
    mImprimir   msgPromptSalir
    CALL CapturarLinea
    CMP  EAX, 1
    JNE  CancelarSalida

    MOVZX EAX, BYTE PTR [bufferEntrada]
    CMP  AL, 'S'
    JE   PermitirSalida
    CMP  AL, 's'
    JE   PermitirSalida

CancelarSalida:
    XOR  EAX, EAX
    JMP  FinConfirmarSalida

PermitirSalida:
    MOV  EAX, 1

FinConfirmarSalida:
    RET
ConfirmarSalida ENDP

END main
