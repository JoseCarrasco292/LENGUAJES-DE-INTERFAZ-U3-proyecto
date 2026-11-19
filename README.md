[readme (2).md](https://github.com/user-attachments/files/35065265/readme.2.md)
# Sistema de Ventas e Inventario en Ensamblador (MASM x86 32-bit + Irvine32) — Versión Unidad 3

**Autor:** José Mario Carrasco Larios  
**Materia:** Lenguajes de Interfaz — Unidades 2 y 3  
**Arquitectura:** x86 de 32 bits (Microsoft Macro Assembler `MASM` + Biblioteca `Irvine32`)  
**Negocio elegido:** Tienda de Videojuegos y Accesorios **PixelVault Gaming**

Sistema de consola desarrollado en lenguaje ensamblador x86 de 32 bits para gestionar el catálogo, entradas de almacén, ventas con regla de negocio de mayoreo, resumen financiero y persistencia en archivo de hasta 10 productos. En la **Versión de la Unidad 3**, el sistema fue refactorizado mediante **procedimientos reutilizables**, **macros parametrizadas con etiquetas `LOCAL`** y la **directiva `USES`**, reduciendo la repetición de código fuente en un **29.1%** de líneas efectivas mientras conserva íntegramente todas las funciones, validaciones y conversiones numéricas propias de la Unidad 2.

## Archivos del Repositorio

| Archivo | Descripción |
| :--- | :--- |
| `main.asm` | Código fuente en ensamblador MASM x86 de 32 bits refactorizado (Unidad 3: procedimientos reutilizables, macros con `LOCAL` y directiva `USES`). |
| `inventario.txt` | Catálogo de prueba con 5 productos precargados en formato delimitado por `\|`. |
| `Informe_Proyecto_Ensamblador.pdf` | Reporte técnico integrado (Unidades 2 y 3) con tabla de antes y después, fragmentos de código, comparativa de líneas y tabla de pruebas actualizada. |

## Mejoras Implementadas en la Versión de la Unidad 3 (`main.asm`)

1. **Extracción de Procedimientos Reutilizables:**
   - `CapturarYBuscarProducto PROC USES EBX EDX EDI`: Centraliza la verificación de inventario vacío, captura del código, validación de formato `ABC-123` y búsqueda con `ESI` que antes se repetía en `ConsultarPorCodigo`, `RecibirMercancia` y `VenderProducto`. Devuelve `EAX` (estado) y `ESI` (puntero al producto).
   - `CapturarCantidadValida PROC USES EAX ECX EDX ESI`: Unifica el ciclo de captura y validación de cantidades enteras en el rango `[1..100]` compartido por `RecibirMercancia` y `VenderProducto`, devolviendo la cantidad validada en `EBX`.
   - `InsertarRegistroEnArreglo PROC USES EAX ECX EDX ESI EDI`: Unifica el cálculo de desplazamiento (`indice * 48`) y la escritura de los campos de un producto tanto en `catalogo` (altas) como en `catalogoTemp` (carga transaccional desde archivo).
2. **Macros con Parámetros y Etiquetas `LOCAL`:**
   - `mVerificarRango regValor, limInf, limSup, etqError` (con `LOCAL EnRango`): Evalúa límites sin signo (`CMP` + `JB` + `JA`) reutilizada en `ValidarCodigoFormato`, `ValidarNombreFormato`, `ValidarYConvertirEntero`, `ValidarYConvertirPrecio` y `CapturarCantidadValida`.
   - `mImprimir` y `mImprimirLn`: Sustituyen más de 90 secuencias repetitivas `MOV EDX, OFFSET ...` + `CALL WriteString` + `CALL Crlf` preservando `EDX`.
   - `mMostrarEtiquetaEntero`, `mMostrarEtiquetaImporte` y `mAgregarCampoArchivo`: Simplifican la impresión de resúmenes/tickets en `MXN` y la serialización de campos hacia `bufferArchivo`.
3. **Aplicación Correcta de la Directiva `USES`:**
   - Todos los procedimientos utilizan `USES` para generar automáticamente el prólogo `PUSH` y el epílogo `POP` de los registros modificados, **excluyendo de `USES` los registros que devuelven resultados** (`EAX` en `CapturarLinea` y `ValidarCodigoFormato`; `EAX` y `EBX` en `ValidarYConvertirEntero` y `ValidarYConvertirPrecio`; `EAX`, `EBX` y `ESI` en `BuscarPorCodigoEnArreglo`).

## Comparación de Líneas de Código Fuente (Unidad 2 vs. Unidad 3)

| Métrica (medida con el mismo criterio en `main.asm`) | Versión Unidad 2 | Versión Unidad 3 | Reducción / Impacto |
| :--- | :---: | :---: | :--- |
| **Líneas totales en el archivo `.asm`** | `2,758` | `2,082` | **-676 líneas (-24.5%)** |
| **Líneas efectivas de código (sin comentarios ni blancos)** | `1,846` | `1,308` | **-538 líneas (-29.1%)** |
| **Instrucciones `PUSH` / `POP` explícitas en `.code`** | `284` | `40` | **-244 líneas (-85.9%)** gracias a `USES` y macros |
| **Llamadas directas `CALL WriteString` en `.code`** | `102` | `10` | **-92 bloques (-90.2%)** encapsulados en `mImprimir` / `mImprimirLn` |

## Organización de Datos en Memoria (`PROD_SIZE = 48` bytes)

| Constante | Desplazamiento | Tamaño y Tipo | Descripción y Restricciones |
| :--- | :---: | :--- | :--- |
| `OFF_CODIGO` | `+0` a `+7` | `8 BYTEs` | Código único en formato `ABC-123` (3 mayúsculas, guion, 3 dígitos) + `00h`. |
| `OFF_NOMBRE` | `+8` a `+35` | `28 BYTEs` | Nombre del producto de 1 a 25 caracteres ASCII visibles + `00h` + relleno. |
| `OFF_PRECIO` | `+36` a `+39` | `1 DWORD (4 B)` | Precio unitario en centavos enteros (`1` a `999999` centavos = `$0.01` a `$9999.99 MXN`). |
| `OFF_EXIST` | `+40` a `+43` | `1 DWORD (4 B)` | Existencia actual disponible en almacén (`0` a `100` unidades). |
| `OFF_VEND` | `+44` a `+47` | `1 DWORD (4 B)` | Unidades vendidas acumuladas del producto en la sesión. |

## Instrucciones de Compilación en Visual Studio

1. Abrir **Visual Studio 2019 o 2022** con soporte para C++ y configurar el proyecto en plataforma **Win32 / x86 (32 bits)** con la biblioteca **Irvine32** en `C:\Irvine`.
2. En el *Explorador de soluciones*, hacer clic derecho en el proyecto -> **Dependencias de compilación** -> **Personalizaciones de compilación...** y activar **masm (.targets, .props)**.
3. Agregar `main.asm` a *Source Files* y colocar `inventario.txt` en la carpeta raíz del proyecto (junto al archivo `.vcxproj`).
4. Verificar en **Propiedades del proyecto**:
   - *Microsoft Macro Assembler -> General -> Include Paths*: `C:\Irvine`
   - *Linker -> General -> Additional Library Directories*: `C:\Irvine`
   - *Linker -> Input -> Additional Dependencies*: `Irvine32.lib`
5. Compilar con `Ctrl + Shift + B` y ejecutar con `Ctrl + F5`.
