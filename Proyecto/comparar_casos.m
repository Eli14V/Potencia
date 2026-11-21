function [comparacion, mayores_cambios] = comparar_casos(archivo_resultados, nombre_caso, ...
    modificar_datos, metodo, datos_barras, baseMVA, resumen, resumen_sistema, tabla_lineas, caso_actual)
% El input 0 guarda el caso base y el input 1 guarda el caso modificado.
% Cada metodo conserva sus magnitudes y flujos durante la sesion de MATLAB.
hoja = 'compara_caso';
% Los identificadores se conservan en MATLAB, sin escribirlos en Excel.
persistent casos_guardados configuracion_guardada archivo_guardado
nombres_metodos = {'Newton-Raphson', 'Gauss-Seidel', 'Desacoplado rapido (XB)'};
configuracion = {nombre_caso, size(datos_barras, 1), baseMVA, resumen.Tolerancia_pu};
num_ramas = height(tabla_lineas);
valores = nan(14, 2);
magnitudes = nan(8, 2, 3);
flujos = nan(num_ramas, 2, 3);
casos = strings(1, 2);

% Columnas donde se conservan los datos de NR, GS y DR dentro de la misma hoja.
columnas_magnitudes = {'K4:L11', 'Q4:R11', 'W4:X11'};
columnas_flujos = {'M', 'N'; 'S', 'T'; 'Y', 'Z'};

%% Recuperar los casos guardados para la misma red y tolerancia
if isequal(archivo_guardado, archivo_resultados) && ...
        isequal(configuracion_guardada, configuracion) && ...
        any(strcmp(sheetnames(archivo_resultados), hoja))
    configuracion_anterior = readcell(archivo_resultados, 'Sheet', hoja, 'Range', 'A2:D2');
    if isequal(configuracion_anterior, configuracion)
        valores = readmatrix(archivo_resultados, 'Sheet', hoja, 'Range', 'B5:C18');
        casos = casos_guardados;
        formato_por_metodo = readcell(archivo_resultados, 'Sheet', hoja, 'Range', 'J1:J1');
        if isequal(formato_por_metodo, nombres_metodos(1))
            for m = 1:3
                magnitudes(:, :, m) = readmatrix(archivo_resultados, ...
                    'Sheet', hoja, 'Range', columnas_magnitudes{m});
                rango = sprintf('%s17:%s%d', columnas_flujos{m, 1}, ...
                    columnas_flujos{m, 2}, 16 + num_ramas);
                flujos(:, :, m) = readmatrix(archivo_resultados, 'Sheet', hoja, 'Range', rango);
            end
        else
            % En los informes anteriores, las magnitudes guardadas eran de NR.
            magnitudes(:, :, 1) = valores(1:8, :);
        end
    end
end

%% Identificar la columna que corresponde al caso base o modificado
caso_actual = string(caso_actual);
columna = 1 + (modificar_datos == 1);

if casos(columna) ~= caso_actual
    if columna == 1 && casos(1) ~= ""
        % Un cambio del caso base inicia una nueva comparacion completa.
        valores = nan(14, 2);
        magnitudes = nan(8, 2, 3);
        flujos = nan(num_ramas, 2, 3);
        casos = strings(1, 2);
    else
        % Un escenario nuevo reinicia su columna para los tres metodos.
        valores(:, columna) = NaN;
        magnitudes(:, columna, :) = NaN;
        flujos(:, columna, :) = NaN;
    end
end
casos(columna) = caso_actual;

%% Guardar las magnitudes y los flujos del metodo seleccionado
% Vmin, barra Vmin, Vmax, barra Vmax, barras fuera de rango, P/Q Slack y perdidas P.
indices_resumen = [11, 12, 13, 14, 15, 16, 17, 5];
magnitudes(:, columna, metodo) = resumen_sistema.Valor(indices_resumen);
flujos(:, columna, metodo) = tabla_lineas.S_max_MVA;
valores(1:8, :) = magnitudes(:, :, metodo);
valores(8 + metodo, columna) = resumen.Iteraciones;
valores(11 + metodo, columna) = double(resumen.Convergio);

Variable = [resumen_sistema.Magnitud(indices_resumen); ...
    {'Iteraciones Newton-Raphson'; 'Iteraciones Gauss-Seidel'; ...
    'Iteraciones desacoplado rapido'; 'Convergio Newton-Raphson (1=si, 0=no)'; ...
    'Convergio Gauss-Seidel (1=si, 0=no)'; 'Convergio desacoplado rapido (1=si, 0=no)'}];
Unidad = [resumen_sistema.Unidad(indices_resumen); ...
    {'iteraciones'; 'iteraciones'; 'iteraciones'; 'indicador'; 'indicador'; 'indicador'}];
Diferencia = valores(:, 2) - valores(:, 1);
Diferencia([2, 4, 12, 13, 14]) = NaN;
comparacion = table(Variable, valores(:, 1), valores(:, 2), Diferencia, Unidad, ...
    'VariableNames', {'Variable', 'Caso_base', 'Caso_modificado', 'Diferencia', 'Unidad'});

%% Comparar los flujos de ambas corridas del mismo metodo
S_base = flujos(:, 1, metodo);
S_modificado = flujos(:, 2, metodo);
Cambio_MVA = S_modificado - S_base;
Cambio_porcentaje = nan(num_ramas, 1);
completos = isfinite(Cambio_MVA);
con_flujo_base = completos & S_base ~= 0;
Cambio_porcentaje(con_flujo_base) = ...
    100*Cambio_MVA(con_flujo_base)./S_base(con_flujo_base);

Observacion = repmat("Pendiente", num_ramas, 1);
if all(valores(11 + metodo, :) == 1)
    Observacion(completos) = "Convergio";
else
    Observacion(completos) = "Ultima aproximacion";
end
sin_flujo_base = completos & S_base == 0;
Observacion(sin_flujo_base) = Observacion(sin_flujo_base) + " / Sin flujo base";

comparacion_flujos = table(tabla_lineas.Rama, tabla_lineas.Desde, tabla_lineas.Hasta, ...
    S_base, S_modificado, Cambio_MVA, Cambio_porcentaje, Observacion, ...
    'VariableNames', {'Rama', 'Desde', 'Hasta', 'Base_MVA', 'Modificado_MVA', ...
    'Cambio_MVA', 'Cambio_porcentaje', 'Observacion'});
indices_completos = find(completos);
[~, orden] = sort(abs(Cambio_MVA(indices_completos)), 'descend');
indices_mayores = indices_completos(orden(1:min(5, numel(orden))));
mayores_cambios = comparacion_flujos(indices_mayores, :);

%% Escribir las tres tablas y conservar los datos de cada metodo
fila_flujos = 27;
fila_mayores = fila_flujos + num_ramas + 4;
ultima_fila = max(fila_mayores + height(mayores_cambios) + 1, 16 + num_ramas);
contenido = cell(ultima_fila, 26);
contenido(1, 1:4) = {'Caso', 'Barras', 'Base_MVA', 'Tolerancia_pu'};
contenido(2, 1:4) = configuracion;
contenido(4, 1:5) = comparacion.Properties.VariableNames;
contenido(5:18, 1:5) = table2cell(comparacion);
contenido(21, 1:2) = {'Metodo de las magnitudes y flujos', nombres_metodos{metodo}};
contenido(22, 1) = {'Diferencia = modificado menos base. Convergencia: 1 = si, 0 = ultima aproximacion.'};
contenido(23, 1) = {'Celdas vacias: resultados pendientes o porcentaje sin flujo base.'};
contenido(25, 1) = {sprintf('Flujos aparentes de todas las ramas - %s', nombres_metodos{metodo})};
contenido(fila_flujos, 1:8) = comparacion_flujos.Properties.VariableNames;
contenido(fila_flujos + (1:num_ramas), 1:8) = table2cell(comparacion_flujos);
contenido(fila_mayores - 1, 1) = ...
    {sprintf('Las 5 ramas de mayor cambio absoluto en MVA - %s', nombres_metodos{metodo})};
contenido(fila_mayores, 1:8) = mayores_cambios.Properties.VariableNames;
contenido(fila_mayores + (1:height(mayores_cambios)), 1:8) = table2cell(mayores_cambios);

% Cada bloque de la derecha conserva un metodo para recuperarlo en otra corrida.
for m = 1:3
    c = 10 + 6*(m - 1);
    contenido(1, c) = nombres_metodos(m);
    contenido(3, c:c+2) = {'Magnitud', 'Caso_base', 'Caso_modificado'};
    contenido(4:11, c) = Variable(1:8);
    contenido(4:11, c+1:c+2) = num2cell(magnitudes(:, :, m));
    contenido(16, c:c+4) = {'Rama', 'Desde', 'Hasta', 'Base_MVA', 'Modificado_MVA'};
    contenido(16 + (1:num_ramas), c:c+4) = ...
        num2cell([tabla_lineas{:, {'Rama', 'Desde', 'Hasta'}}, flujos(:, :, m)]);
end
writecell(contenido, archivo_resultados, 'Sheet', hoja, ...
    'Range', 'A1', 'WriteMode', 'overwritesheet');
casos_guardados = casos;
configuracion_guardada = configuracion;
archivo_guardado = archivo_resultados;
end
