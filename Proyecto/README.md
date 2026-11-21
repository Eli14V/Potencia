# Proyecto de flujos de potencia en MATLAB

El programa calcula el estado de una red eléctrica mediante tres métodos:
**Newton-Raphson, Gauss-Seidel y desacoplado rápido XB**. Obtiene tensiones,
ángulos, flujos aparentes por rama, pérdidas y generación de la barra Slack.

El estudio principal utiliza el sistema IEEE de **118 barras**. También se
incluyen casos completos de **4, 9, 14 y 57 barras**. El tamaño de las matrices
se determina a partir de los datos seleccionados.

## Requisitos

- MATLAB y esta carpeta completa, incluidos sus archivos `.m`, `casos` y `Validaciones`.
- MATPOWER instalado y agregado al path de MATLAB **solo para ejecutar la validación**.
  La validación se preparó con MATPOWER 8.1.

## Cómo ejecutar el programa

1. Descargar o clonar el repositorio y abrir MATLAB.
2. Establecer la carpeta **`Proyecto`** como carpeta actual de MATLAB.
3. Cerrar los Excel de entrada y salida para permitir que el programa escriba en ellos.
4. Ejecutar [Proyecto_potencia.m](Proyecto_potencia.m) con **Run**, o escribir:

   ```matlab
   Proyecto_potencia
   ```

5. En la ventana de selección, abrir `casos` y elegir un archivo como `case118.m`.
   Seleccionar un archivo de datos, no uno de los métodos numéricos.
6. Elegir una opción del menú:

   | Opción | Acción |
   |---|---|
   | 1 | Newton-Raphson |
   | 2 | Gauss-Seidel |
   | 3 | Desacoplado rápido XB |
   | 4 | Editar los datos en Excel y volver a cargarlos |
   | 0 | Terminar |

7. Introducir una tolerancia positiva, por ejemplo **`1e-8`**. El programa calcula,
   guarda los resultados y vuelve al menú para ejecutar otro método.

Para comparar los tres métodos, ejecutarlos con **el mismo caso y la misma
tolerancia**. Los máximos de iteraciones son 30 para Newton, 10000 para Gauss y
100 para desacoplado; cada método termina antes si alcanza la tolerancia.

## Excel de entrada: Proyecto_datos.xlsx

Al iniciar, el programa exporta el caso seleccionado a este libro y luego lo lee
para formar las matrices de trabajo. Tiene cuatro hojas:

| Hoja | Contenido |
|---|---|
| `Barras` | Identificador, tipo PQ/PV/Slack, demandas, shunts y datos de tensión. |
| `Generadores` | Barra de conexión, potencias, tensión especificada, estado y límites registrados de cada generador. |
| `Lineas` | Líneas y transformadores: extremos, R, X, susceptancia, tap, desfase y estado. |
| `Base` | Potencia base del sistema; en el caso de 118 barras es **100 MVA**. |

Los encabezados están en la **fila 1** y los datos comienzan en la **fila 2**.
Las potencias se expresan en MW/MVAr, las tensiones e impedancias correspondientes
en pu y los ángulos en grados. Los shunts están en `Gs_MW` y `Bs_MVAr` de `Barras`.

### Editar un escenario

Primero ejecutar los tres métodos del caso base y conservar copias de ambos Excel.
Después, elegir **4**, editar `Proyecto_datos.xlsx` conservando su estructura,
guardar y cerrar Excel, y confirmar con **1** en MATLAB. Ejecutar de nuevo los
métodos con la misma tolerancia.

Por ejemplo, para el **escenario 4**, buscar la barra **118** en `Barras` y cambiar
`Pd_MW` de **33 a 133 MW**, y `Qd_MVAr` de **15 a 65 MVAr**. Con el orden actual,
son las celdas **C119 y D119**.

Realizar base y escenario en la **misma sesión**, sin usar `clear all`. Reiniciar
el principal vuelve a exportar el caso original y reemplaza la entrada editada.

## Excel de salida: Proyecto_resultados.xlsx

| Hoja | Contenido |
|---|---|
| `NR` | Resultados de la última corrida de Newton-Raphson. |
| `GS` | Resultados de la última corrida de Gauss-Seidel. |
| `DR` | Resultados de la última corrida del desacoplado rápido. |
| `compara_meto` | Iteraciones, tiempo, desbalance final, P de la Slack, pérdidas P/Q y estado de los tres métodos para los mismos datos y tolerancia. |
| `compara_caso` | Comparación base/escenario por método y las cinco ramas con mayor cambio absoluto de flujo aparente. |

En `NR`, `GS` y `DR` aparecen tensiones en pu, ángulos en grados e inyecciones
netas P/Q en pu (generación menos demanda), junto con iteraciones, desbalance,
tiempo y convergencia. Debajo están los totales, la generación Slack, las cinco
barras de menor tensión y los flujos aparentes de las ramas.

Los flujos muestran `Desde`, `Hasta` y `S_MVA`, el mayor módulo aparente entre
extremos. Las pérdidas Q comparadas son consumo reactivo serie; el aporte
capacitivo se informa aparte. **`Convergio = 0/false` indica última aproximación**,
no una solución convergida.

Cada cálculo **reemplaza la hoja del método seleccionado**. Las demás pueden
conservar otra corrida. Guardar copias identificadas como base y escenario para
mantener la evidencia de ambos estudios.

## Validación con MATPOWER

[Validaciones/validar_caso.m](Validaciones/validar_caso.m) ejecuta automáticamente
los tres métodos propios y los compara con **Newton-Raphson de MATPOWER**, usando
el archivo original del **caso base**.

Desde la carpeta `Proyecto`, con MATPOWER disponible en el path:

```matlab
cd Validaciones
validar_caso
```

Seleccionar `casos/case118.m` en la ventana. Cerrar previamente el libro de
validación si está abierto. No es necesario ejecutar antes el programa principal.

El informe se guarda en **`Validaciones/Validacion_resultados.xlsx`**, en una hoja
como `caso118`. Compara tensiones, ángulos, inyecciones P/Q, pérdidas y generación
Slack e indica **`Aprobado`** por método. Usa tolerancia propia `1e-8 pu` y de
referencia `1e-10 pu`.

La validación **no usa el escenario editado en Excel**. Comparar su informe con
la copia de resultados del caso base, no con una hoja ya reemplazada por el
escenario. Los archivos que empiezan por `~$` son temporales de Excel, no informes.

## Alcance

Los métodos parten de un perfil plano adaptado a PV/Slack. No se imponen los
límites `Qmin/Qmax` ni se realiza conversión automática de PV a PQ; MATPOWER se
configura de la misma manera para validar. **Converger no garantiza que se
cumplan todos los límites operativos de los equipos.**
