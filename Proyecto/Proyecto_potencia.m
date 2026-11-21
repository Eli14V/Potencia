%% Seleccionar el caso y exportarlo a Excel
[nombre_archivo, ruta_archivo] = uigetfile( ...
    '*.m', 'Seleccione el archivo de datos del sistema');

% Detener el programa si se canceló la selección
if isequal(nombre_archivo, 0)
    archivo = 0;
    nombre_caso = '';
    return;
end

% Guardar la ubicación completa y el nombre de la función del caso.
archivo_seleccionado = fullfile(ruta_archivo, nombre_archivo);
[~, nombre_caso] = fileparts(nombre_archivo);

%% Cargar los datos del archivo seleccionado
carpeta_original = pwd;
cd(ruta_archivo);

try
    mpc = feval(nombre_caso);
catch error_carga
    % Regresar a la carpeta original si ocurre un error al cargar el caso.
    cd(carpeta_original);
    rethrow(error_carga);
end
cd(carpeta_original);

%% Exportar los datos al Excel de entrada
carpeta_proyecto = fileparts(mfilename('fullpath'));
archivo = fullfile(carpeta_proyecto, 'Proyecto_datos.xlsx');

% Encabezados en el mismo orden de las columnas de MATPOWER.
encabezados_barras = {'Barra', 'Tipo', 'Pd_MW', 'Qd_MVAr', 'Gs_MW', 'Bs_MVAr', ...
    'Area', 'Vm_pu', 'Va_grados', 'Base_kV', 'Zona', 'Vmax_pu', 'Vmin_pu'};
encabezados_gen = {'Barra', 'Pg_MW', 'Qg_MVAr', 'Qmax_MVAr', 'Qmin_MVAr', ...
    'Vg_pu', 'Base_MVA', 'Estado', 'Pmax_MW', 'Pmin_MW', 'Pc1_MW', 'Pc2_MW', ...
    'Qc1min_MVAr', 'Qc1max_MVAr', 'Qc2min_MVAr', 'Qc2max_MVAr', ...
    'Rampa_AGC_MW_min', 'Rampa_10_MW', 'Rampa_30_MW', 'Rampa_Q_MVAr_min', 'APF'};
encabezados_lineas = {'Desde', 'Hasta', 'R_pu', 'X_pu', 'B_pu', ...
    'Limite_A_MVA', 'Limite_B_MVA', 'Limite_C_MVA', 'Tap', ...
    'Desfase_grados', 'Estado', 'Angulo_min_grados', 'Angulo_max_grados'};

% Reemplazar las hojas y escribir encabezados en la fila 1 y datos desde la fila 2.
writetable(array2table(mpc.bus, 'VariableNames', encabezados_barras), ...
    archivo, "Sheet", "Barras", "WriteMode", "overwritesheet");
writetable(array2table(mpc.gen, 'VariableNames', encabezados_gen), ...
    archivo, "Sheet", "Generadores", "WriteMode", "overwritesheet");
writetable(array2table(mpc.branch, 'VariableNames', encabezados_lineas), ...
    archivo, "Sheet", "Lineas", "WriteMode", "overwritesheet");
writetable(array2table(mpc.baseMVA, 'VariableNames', {'Base_MVA'}), ...
    archivo, "Sheet", "Base", "WriteMode", "overwritesheet");

disp("Datos exportados correctamente a Excel:");
disp(archivo);

%% Leer el caso base una sola vez desde Excel
datos_barras = readmatrix(archivo, "Sheet", "Barras", "Range", "A2");
datos_gen = readmatrix(archivo, "Sheet", "Generadores", "Range", "A2");
datos_lineas = readmatrix(archivo, "Sheet", "Lineas", "Range", "A2");
baseMVA = readmatrix(archivo, "Sheet", "Base", "Range", "A2");

% El caso comienza como base y pasa a modificado al utilizar la opcion 4.
modificar_datos = 0;
tipos_caso = {'Caso base', 'Caso modificado'};
hojas_metodos = {'NR', 'GS', 'DR'};
archivo_resultados = fullfile(carpeta_proyecto, 'Proyecto_resultados.xlsx');

%% Menu para repetir calculos con los datos actuales
while true
    num_barras = size(datos_barras, 1);
    num_gen = size(datos_gen, 1);
    num_lineas = size(datos_lineas, 1);
    fprintf('\n%s | %s\n', nombre_caso, tipos_caso{modificar_datos + 1});
    fprintf('Barras: %d | Generadores: %d | Lineas y transformadores: %d\n', ...
        num_barras, num_gen, num_lineas);
    disp('1 = Newton-Raphson');
    disp('2 = Gauss-Seidel');
    disp('3 = Desacoplado rapido (XB)');
    disp('4 = Editar datos en Excel');
    disp('0 = Terminar');
    metodo = str2double(input('Seleccione una opcion: ', 's'));

    switch metodo
        case 0
            disp('Programa finalizado.');
            break;

        case 4
            fprintf('Abra el siguiente archivo para realizar los cambios:\n%s\n', archivo);
            disp('Una vez editado el excel, conserve las filas y columnas. Guarde y cierre el Excel antes de continuar.');

            datos_listos = 0;
            while datos_listos ~= 1
                datos_listos = str2double(input('Los datos ya estan guardados y el Excel cerrado? (1 = Si, 0 = No): ', 's'));
            end

            % Actualizar las matrices unicamente cuando se confirma la edicion.
            datos_barras = readmatrix(archivo, "Sheet", "Barras", "Range", "A2");
            datos_gen = readmatrix(archivo, "Sheet", "Generadores", "Range", "A2");
            datos_lineas = readmatrix(archivo, "Sheet", "Lineas", "Range", "A2");
            baseMVA = readmatrix(archivo, "Sheet", "Base", "Range", "A2");
            modificar_datos = 1;
            disp('Datos actualizados. Seleccione un metodo para calcular el escenario.');
            continue;

        case 1
            tol = str2double(input('Tolerancia para Newton-Raphson (ejemplo: 1e-6): ', 's'));
            max_iter = 30;
            nombre_metodo = 'Newton-Raphson';
            [tabla_resultados, converge, iter, error_max, tiempo] = ...
                Newton_Raphson(datos_barras, datos_gen, datos_lineas, ...
                               baseMVA, tol, max_iter);

        case 2
            tol = str2double(input('Tolerancia para Gauss-Seidel (ejemplo: 1e-6): ', 's'));
            max_iter = 10000;
            nombre_metodo = 'Gauss-Seidel';
            [tabla_resultados, converge, iter, error_max, tiempo] = ...
                Gauss_Seidel(datos_barras, datos_gen, datos_lineas, ...
                             baseMVA, tol, max_iter);

        case 3
            tol = str2double(input('Tolerancia para desacoplado rapido (ejemplo: 1e-6): ', 's'));
            max_iter = 100;
            nombre_metodo = 'Desacoplado rapido (XB)';
            [tabla_resultados, converge, iter, error_max, tiempo] = ...
                Desacoplado_Rapido(datos_barras, datos_gen, datos_lineas, ...
                                   baseMVA, tol, max_iter);

        otherwise
            disp('Seleccione 0, 1, 2, 3 o 4.');
            continue;
    end

    %% Presentar y guardar el resultado del metodo seleccionado
    if converge
        fprintf('%s convergio correctamente.\n', nombre_metodo);
    else
        warning('No se alcanzo la convergencia. Se muestra la ultima aproximacion.');
    end
    disp(tabla_resultados);
    fprintf('Iteraciones realizadas: %d\n', iter);
    fprintf('Desbalance maximo final: %.6e pu\n', error_max);
    fprintf('Tiempo del metodo: %.6f segundos\n', tiempo);

    resumen = table(tol, max_iter, iter, error_max, tiempo, converge, ...
        'VariableNames', {'Tolerancia_pu', 'Max_iteraciones', 'Iteraciones', ...
                         'Error_final_pu', 'Tiempo_solver_s', 'Convergio'});
    hoja_resultados = hojas_metodos{metodo};
    writetable(tabla_resultados, archivo_resultados, 'Sheet', hoja_resultados, ...
               'Range', 'A1', 'WriteMode', 'overwritesheet');
    writetable(resumen, archivo_resultados, 'Sheet', hoja_resultados, ...
               'Range', 'I1', 'WriteMode', 'inplace');

    %% Calcular flujos, perdidas, Slack y resumenes
    [tabla_lineas, resumen_sistema, tabla_slack, menores_tensiones, mayores_flujos] = ...
        calcular_resultados(datos_barras, datos_lineas, baseMVA, tabla_resultados);

    % Presentar los extremos de cada rama y su mayor potencia aparente en MVA.
    columnas_flujos = {'Desde', 'Hasta', 'S_max_MVA'};
    flujos_ramas = tabla_lineas(:, columnas_flujos);
    flujos_ramas.Properties.VariableNames = {'Desde', 'Hasta', 'S_MVA'};
    mayores_flujos = mayores_flujos(:, columnas_flujos);
    mayores_flujos.Properties.VariableNames = {'Desde', 'Hasta', 'S_MVA'};
    disp('Resumen del sistema (si no convergio, corresponde a la ultima aproximacion):');
    disp(resumen_sistema);
    disp('Generacion de la barra Slack:');
    disp(tabla_slack);
    disp('Las 5 barras de menor tension:');
    disp(menores_tensiones);
    disp('Las 5 ramas de mayor flujo de potencia aparente:');
    disp(mayores_flujos);

    %% Agregar las tablas debajo de los resultados actuales, en la misma hoja
    titulos = {'Resumen del sistema'; 'Generacion de la Slack'; ...
        'Barras de menor tension'; 'Ramas de mayor flujo de potencia aparente'; ...
        'Flujo aparente de todas las ramas (MVA)'};
    tablas = {resumen_sistema; tabla_slack; menores_tensiones; mayores_flujos; flujos_ramas};
    fila = max(height(tabla_resultados) + 4, 6);
    for k = 1:numel(tablas)
        writecell(titulos(k), archivo_resultados, 'Sheet', hoja_resultados, ...
                  'Range', sprintf('A%d', fila), 'WriteMode', 'inplace');
        writetable(tablas{k}, archivo_resultados, 'Sheet', hoja_resultados, ...
                   'Range', sprintf('A%d', fila + 1), 'WriteMode', 'inplace');
        fila = fila + height(tablas{k}) + 4;
    end
    fprintf('Resultados y resumenes guardados en: %s (hoja %s)\n', ...
        archivo_resultados, hoja_resultados);

    %% Actualizar las comparaciones de metodos y de casos
    [tabla_comparativa, caso] = comparar_metodos(archivo_resultados, metodo, datos_barras, ...
        datos_gen, datos_lineas, baseMVA, resumen, tabla_slack, tabla_lineas);
    disp('Se muestra la Tabla comparativa entre los metodos para los mismos datos y tolerancia:');
    disp(tabla_comparativa);

    [tabla_casos, mayores_cambios] = comparar_casos(archivo_resultados, nombre_caso, ...
        modificar_datos, metodo, datos_barras, baseMVA, resumen, resumen_sistema, tabla_lineas, caso);
    % Mostrar las comparaciones de escenario despues de calcular el caso modificado.
    if modificar_datos == 1
        disp('Comparacion del caso base y el caso modificado:');
        disp(tabla_casos);
        disp('Las 5 ramas con mayor cambio de flujo para el metodo seleccionado:');
        disp(mayores_cambios);
    end
    disp('Estas comparaciones se guardan en el Excel de resultados en las hojas de "compara_meto" y "compara_caso".');
end
