function [comparacion, caso] = comparar_metodos(archivo_resultados, metodo, datos_barras, ...
    datos_gen, datos_lineas, baseMVA, resumen, tabla_slack, tabla_lineas)
% Actualiza una fila por corrida y conserva las otras del mismo estudio.
hoja = 'compara_meto';
% Conservar la identificacion entre llamadas, solamente dentro de MATLAB.
persistent caso_anterior archivo_anterior

%% Identificar los datos y la tolerancia usados en la comparacion
% El identificador cambia al editar cualquier dato y permite reconocer la red.
texto_datos = [mat2str(datos_barras, 17), '|', mat2str(datos_gen, 17), '|', ...
    mat2str(datos_lineas, 17), '|', mat2str(baseMVA, 17), '|', ...
    mat2str(resumen.Tolerancia_pu, 17)];
generador_caso = java.security.MessageDigest.getInstance('SHA-256');
generador_caso.update(unicode2native(texto_datos, 'UTF-8'));
bytes_caso = typecast(generador_caso.digest(), 'uint8');
caso = lower(reshape(dec2hex(bytes_caso, 2).', 1, []));

%% Preparar las tres filas, inicialmente pendientes
Metodo = ["Newton-Raphson"; "Gauss-Seidel"; "Desacoplado rapido (XB)"];
comparacion = table(Metodo, nan(3, 1), nan(3, 1), nan(3, 1), ...
    nan(3, 1), nan(3, 1), nan(3, 1), repmat("Pendiente", 3, 1), ...
    'VariableNames', {'Metodo', 'Iteraciones', 'Tiempo_computo_s', ...
    'Mismatch_final_pu', 'P_slack_MW', 'Perdidas_P_MW', 'Perdidas_Q_MVAr', 'Estado'});

% Recuperar las filas anteriores solamente cuando pertenecen al mismo estudio.
if isequal(archivo_anterior, archivo_resultados) && isequal(caso_anterior, caso) && ...
        any(strcmp(sheetnames(archivo_resultados), hoja))
    comparacion{:, 2:7} = readmatrix(archivo_resultados, 'Sheet', hoja, 'Range', 'B5:G7');
    comparacion.Estado = string(readcell(archivo_resultados, 'Sheet', hoja, 'Range', 'H5:H7'));
end

%% Completar la fila del metodo que acaba de ejecutarse
comparacion{metodo, 2:7} = [resumen.Iteraciones, resumen.Tiempo_solver_s, ...
    resumen.Error_final_pu, sum(tabla_slack.P_generacion_MW), ...
    sum(tabla_lineas.P_perdida_MW), sum(tabla_lineas.Q_perdida_serie_MVAr)];
if resumen.Convergio
    comparacion.Estado(metodo) = "Convergio";
else
    comparacion.Estado(metodo) = "No convergio";
end

%% Escribir configuracion y tabla en la misma hoja
contenido = cell(10, 8);
contenido(1, 1:4) = {'Barras', 'Ramas', 'Base_MVA', 'Tolerancia_pu'};
contenido(2, 1:4) = {size(datos_barras, 1), size(datos_lineas, 1), ...
    baseMVA, resumen.Tolerancia_pu};
contenido(4, :) = comparacion.Properties.VariableNames;
contenido(5:7, :) = table2cell(comparacion);
contenido(9, 1) = {'Perdidas Q: consumo de la impedancia serie, en MVAr.'};
contenido(10, 1) = {'Los flujos y el aporte capacitivo se detallan en la hoja de cada metodo.'};
writecell(contenido, archivo_resultados, 'Sheet', hoja, ...
    'Range', 'A1', 'WriteMode', 'overwritesheet');
caso_anterior = caso;
archivo_anterior = archivo_resultados;
end
