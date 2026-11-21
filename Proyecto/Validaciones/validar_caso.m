function [resumen, archivo_resultados] = validar_caso(archivo_caso)
% Compara los tres métodos del proyecto con Newton-Raphson de MATPOWER.
% Se valida la corrida base cargada del archivo original del caso.
% Ejecutar validar_caso para seleccionar un caso mediante una ventana.
% También admite la ruta del caso: validar_caso('ruta/completa/case14.m').

%% Carpetas y selección del caso
carpeta_validaciones = fileparts(mfilename('fullpath'));
carpeta_proyecto = fileparts(carpeta_validaciones);
addpath(carpeta_proyecto);
resumen = table();
archivo_resultados = '';

if nargin == 0
    [nombre_archivo, ruta_archivo] = uigetfile( ...
        {'case*.m', 'Casos MATPOWER (case*.m)'}, ...
        'Seleccione el caso que desea validar', carpeta_proyecto);
    if isequal(nombre_archivo, 0)
        disp('No se seleccionó ningún caso.');
        return;
    end
    archivo_caso = fullfile(ruta_archivo, nombre_archivo);
end

% Usar el archivo local completo, no otro caso con el mismo nombre en el path.
archivo_caso = char(archivo_caso);
[~, nombre_caso] = fileparts(archivo_caso);
mpc = loadcase(archivo_caso);
archivo_resultados = fullfile(carpeta_validaciones, 'Validacion_resultados.xlsx');
hoja_caso = sprintf('caso%d', size(mpc.bus, 1));

%% Tolerancias de cálculo y criterios de aceptación del proyecto
tol = 1e-8;
tol_referencia = 1e-10;
limite_ybus = 1e-10;
limite_voltaje = 1e-6;
limite_angulo = 1e-4;   % Grados, medidos respecto a la Slack
limite_potencia = 1e-5; % pu, para las inyecciones netas P y Q
limite_totales = limite_potencia*mpc.baseMVA; % MW o MVAr, para perdidas y Slack
metodos = ["NR"; "GS"; "DR"];
max_iteraciones = [30; 10000; 100];

id_barras = mpc.bus(:, 1);
tipo_barra = mpc.bus(:, 2);
idx_slack = find(tipo_barra == 3);
idx_PQ = find(tipo_barra == 1);
idx_PV = find(tipo_barra == 2);
idx_ang = [idx_PV; idx_PQ];

%% Preparar el mismo Flat Start para MATPOWER
caso_referencia = mpc;
caso_referencia.bus(:, 8) = 1;
caso_referencia.bus(:, 9) = mpc.bus(idx_slack, 9);
generadores = mpc.gen(mpc.gen(:, 8) > 0, :);
idx_control = [idx_PV; idx_slack];
for k = 1:numel(idx_control)
    i = idx_control(k);
    voltajes = generadores(generadores(:, 1) == id_barras(i), 6);
    caso_referencia.bus(i, 8) = voltajes(1);
end

%% Referencia externa: Newton polar de MATPOWER
opciones = mpoption('model', 'AC', 'pf.alg', 'NR', ...
    'pf.current_balance', 0, 'pf.v_cartesian', 0, ...
    'pf.enforce_q_lims', 0, 'pf.tol', tol_referencia, ...
    'pf.nr.max_it', 30, 'verbose', 0, 'out.all', 0);
[solucion_mp, exito_mp] = runpf(caso_referencia, opciones);

% Una referencia no convergida no permite aprobar la comparación.
if ~exito_mp
    error('MATPOWER no convergió. No se generó un nuevo informe de validación.');
end

%% Comparar Ybus con la construcción independiente de MATPOWER
% ext2int convierte los identificadores a la numeración interna de MATPOWER.
caso_interno = ext2int(mpc);
Ybus_interna = makeYbus(caso_interno.baseMVA, caso_interno.bus, caso_interno.branch);
[~, orden_interno] = ismember(id_barras, caso_interno.order.bus.i2e);
Ybus_mp = Ybus_interna(orden_interno, orden_interno);
Ybus_propia = construir_Ybus(mpc.bus, mpc.branch, mpc.baseMVA);
error_ybus = max(abs(Ybus_propia - Ybus_mp), [], 'all');

% Inyecciones especificadas originales, para comprobar desbalances por separado.
Sesp_interna = makeSbus(caso_interno.baseMVA, caso_interno.bus, caso_interno.gen);
Sesp = Sesp_interna(orden_interno);

%% Voltajes y potencias netas de la solución de referencia
[~, orden_mp] = ismember(id_barras, solucion_mp.bus(:, 1));
V_mp = solucion_mp.bus(orden_mp, 8);
angulo_mp = solucion_mp.bus(orden_mp, 9);

% makeSbus suma generación en servicio y resta demanda, expresadas en pu.
% Se usan los generadores RESUELTOS para incluir P de Slack y Q de PV/Slack.
solucion_interna = ext2int(solucion_mp);
Smp_interna = makeSbus(solucion_interna.baseMVA, ...
                      solucion_interna.bus, solucion_interna.gen);
[~, orden_solucion] = ismember(id_barras, solucion_interna.order.bus.i2e);
S_mp = Smp_interna(orden_solucion);
P_mp = real(S_mp);
Q_mp = imag(S_mp);
angulo_rel_mp = angulo_mp - angulo_mp(idx_slack);

%% Perdidas y generacion Slack de referencia, en MW y MVAr
% get_losses devuelve las perdidas de la impedancia serie del modelo pi.
perdidas_serie_mp = get_losses(solucion_mp);
perdidas_P_mp = sum(real(perdidas_serie_mp));
perdidas_Q_mp = sum(imag(perdidas_serie_mp));
generadores_slack = ismember(solucion_mp.gen(:, 1), id_barras(idx_slack)) & ...
    solucion_mp.gen(:, 8) > 0;
P_slack_mp = sum(solucion_mp.gen(generadores_slack, 2));
Q_slack_mp = sum(solucion_mp.gen(generadores_slack, 3));

tabla_mp = table(id_barras, V_mp, angulo_mp, P_mp, Q_mp, ...
    'VariableNames', {'Barra', 'V_pu', 'Angulo_grados', 'P_neta_pu', 'Q_neta_pu'});
% Limpiar solamente la hoja de este caso y colocar la referencia desde A11.
% A1:A2 se reserva para configuración y A5:A8 para el resumen de los métodos.
writetable(tabla_mp, archivo_resultados, 'Sheet', hoja_caso, ...
           'Range', 'A11', 'WriteMode', 'overwritesheet');
writecell({'Referencia de MATPOWER'}, archivo_resultados, 'Sheet', hoja_caso, ...
          'Range', 'A10', 'WriteMode', 'inplace');
fila_comparacion = height(tabla_mp) + 14;

%% Ejecutar y comparar los tres métodos del proyecto
convergieron = false(3, 1);
iteraciones = zeros(3, 1);
tiempos = zeros(3, 1);
desbalances = zeros(3, 1);
desbalances_independientes = zeros(3, 1);
errores_V = zeros(3, 1);
errores_angulo = zeros(3, 1);
errores_P = zeros(3, 1);
errores_Q = zeros(3, 1);
perdidas_P = zeros(3, 1);
perdidas_Q = zeros(3, 1);
P_slack = zeros(3, 1);
Q_slack = zeros(3, 1);
errores_perdidas_P = zeros(3, 1);
errores_perdidas_Q = zeros(3, 1);
errores_P_slack = zeros(3, 1);
errores_Q_slack = zeros(3, 1);
aprobado = false(3, 1);

for metodo = 1:3
    switch metodo
        case 1
            [tabla, convergieron(metodo), iteraciones(metodo), ...
                desbalances(metodo), tiempos(metodo)] = ...
                Newton_Raphson(mpc.bus, mpc.gen, mpc.branch, ...
                               mpc.baseMVA, tol, max_iteraciones(metodo));
        case 2
            [tabla, convergieron(metodo), iteraciones(metodo), ...
                desbalances(metodo), tiempos(metodo)] = ...
                Gauss_Seidel(mpc.bus, mpc.gen, mpc.branch, ...
                             mpc.baseMVA, tol, max_iteraciones(metodo));
        case 3
            [tabla, convergieron(metodo), iteraciones(metodo), ...
                desbalances(metodo), tiempos(metodo)] = ...
                Desacoplado_Rapido(mpc.bus, mpc.gen, mpc.branch, ...
                                   mpc.baseMVA, tol, max_iteraciones(metodo));
    end

    % Comparar por identificador de barra, manteniendo el orden del caso original.
    [~, orden_propio] = ismember(id_barras, tabla.Barra);
    tabla = tabla(orden_propio, :);
    error_V = abs(tabla.V_pu - V_mp);
    angulo_rel_propio = tabla.Angulo_grados - tabla.Angulo_grados(idx_slack);
    % angle(exp(j*delta)) evita diferencias falsas de 360 grados.
    error_angulo = abs(rad2deg(angle(exp(1j*deg2rad(angulo_rel_propio - angulo_rel_mp)))));
    error_P = abs(tabla.P_neta_pu - P_mp);
    error_Q = abs(tabla.Q_neta_pu - Q_mp);

    % Comprobar las ecuaciones del método propio usando la Ybus de MATPOWER.
    V_propio = tabla.V_pu .* exp(1j*deg2rad(tabla.Angulo_grados));
    S_propia = V_propio .* conj(Ybus_mp*V_propio);
    error_independiente = [real(Sesp(idx_ang) - S_propia(idx_ang));
                          imag(Sesp(idx_PQ) - S_propia(idx_PQ))];
    desbalances_independientes(metodo) = max([0; abs(error_independiente)]);

    errores_V(metodo) = max(error_V);
    errores_angulo(metodo) = max(error_angulo);
    errores_P(metodo) = max(error_P);
    errores_Q(metodo) = max(error_Q);

    % Aplicar los mismos calculos adicionales que utiliza el programa principal.
    [tabla_lineas, ~, tabla_slack] = ...
        calcular_resultados(mpc.bus, mpc.branch, mpc.baseMVA, tabla);
    perdidas_P(metodo) = sum(tabla_lineas.P_perdida_MW);
    perdidas_Q(metodo) = sum(tabla_lineas.Q_perdida_serie_MVAr);
    P_slack(metodo) = sum(tabla_slack.P_generacion_MW);
    Q_slack(metodo) = sum(tabla_slack.Q_generacion_MVAr);
    errores_perdidas_P(metodo) = abs(perdidas_P(metodo) - perdidas_P_mp);
    errores_perdidas_Q(metodo) = abs(perdidas_Q(metodo) - perdidas_Q_mp);
    errores_P_slack(metodo) = abs(P_slack(metodo) - P_slack_mp);
    errores_Q_slack(metodo) = abs(Q_slack(metodo) - Q_slack_mp);
    cumple_barra = convergieron(metodo) & error_V <= limite_voltaje & ...
        error_angulo <= limite_angulo & error_P <= limite_potencia & ...
        error_Q <= limite_potencia;
    aprobado(metodo) = convergieron(metodo) && all(cumple_barra) && ...
        error_ybus <= limite_ybus && ...
        desbalances(metodo) < tol && desbalances_independientes(metodo) < tol && ...
        errores_perdidas_P(metodo) <= limite_totales && ...
        errores_perdidas_Q(metodo) <= limite_totales && ...
        errores_P_slack(metodo) <= limite_totales && ...
        errores_Q_slack(metodo) <= limite_totales;

    % Tabla de comparación por barra, en un bloque dentro de la hoja del caso.
    comparacion = table(id_barras, tabla.V_pu, V_mp, error_V, ...
        tabla.Angulo_grados, angulo_mp, error_angulo, ...
        tabla.P_neta_pu, P_mp, error_P, tabla.Q_neta_pu, Q_mp, error_Q, cumple_barra, ...
        'VariableNames', {'Barra', 'V_propio_pu', 'V_MATPOWER_pu', 'Error_V_pu', ...
        'Angulo_propio_grados', 'Angulo_MATPOWER_grados', 'Error_angulo_rel_grados', ...
        'P_propio_pu', 'P_MATPOWER_pu', 'Error_P_pu', ...
        'Q_propio_pu', 'Q_MATPOWER_pu', 'Error_Q_pu', 'Cumple_barra'});
    titulo = sprintf('Comparación %s con MATPOWER', char(metodos(metodo)));
    writecell({titulo}, archivo_resultados, 'Sheet', hoja_caso, ...
              'Range', sprintf('A%d', fila_comparacion), 'WriteMode', 'inplace');
    writetable(comparacion, archivo_resultados, 'Sheet', hoja_caso, ...
               'Range', sprintf('A%d', fila_comparacion + 1), 'WriteMode', 'inplace');
    % Dejar dos filas vacías antes del siguiente bloque.
    fila_comparacion = fila_comparacion + height(comparacion) + 4;
end

%% Comparacion de los totales del caso base con la referencia publicada
totales = table(metodos, perdidas_P, repmat(perdidas_P_mp, 3, 1), errores_perdidas_P, ...
    perdidas_Q, repmat(perdidas_Q_mp, 3, 1), errores_perdidas_Q, ...
    P_slack, repmat(P_slack_mp, 3, 1), errores_P_slack, ...
    Q_slack, repmat(Q_slack_mp, 3, 1), errores_Q_slack, ...
    'VariableNames', {'Metodo', 'Perdidas_P_propias_MW', 'Perdidas_P_MATPOWER_MW', ...
    'Error_perdidas_P_MW', 'Perdidas_Q_propias_MVAr', 'Perdidas_Q_MATPOWER_MVAr', ...
    'Error_perdidas_Q_MVAr', 'P_slack_propia_MW', 'P_slack_MATPOWER_MW', ...
    'Error_P_slack_MW', 'Q_slack_propia_MVAr', 'Q_slack_MATPOWER_MVAr', 'Error_Q_slack_MVAr'});
writecell({'Perdidas totales y generacion Slack del caso base'}, ...
    archivo_resultados, 'Sheet', hoja_caso, ...
    'Range', sprintf('A%d', fila_comparacion), 'WriteMode', 'inplace');
writetable(totales, archivo_resultados, 'Sheet', hoja_caso, ...
    'Range', sprintf('A%d', fila_comparacion + 1), 'WriteMode', 'inplace');
writecell({'Perdidas Q corresponden al consumo de la impedancia serie de las ramas.'}, ...
    archivo_resultados, 'Sheet', hoja_caso, ...
    'Range', sprintf('A%d', fila_comparacion + 6), 'WriteMode', 'inplace');

%% Resumen general y configuración registrada para reproducir la prueba
resumen = table(metodos, convergieron, iteraciones, max_iteraciones, tiempos, ...
    desbalances, desbalances_independientes, repmat(error_ybus, 3, 1), ...
    errores_V, errores_angulo, errores_P, errores_Q, ...
    errores_perdidas_P, errores_perdidas_Q, errores_P_slack, errores_Q_slack, aprobado, ...
    'VariableNames', {'Metodo', 'Convergio', 'Iteraciones', 'Max_iteraciones', ...
    'Tiempo_solver_s', 'Desbalance_propio_pu', 'Desbalance_independiente_pu', ...
    'Error_Ybus_pu', 'Error_V_pu', 'Error_angulo_grados', 'Error_P_pu', ...
    'Error_Q_pu', 'Error_perdidas_P_MW', 'Error_perdidas_Q_MVAr', ...
    'Error_P_slack_MW', 'Error_Q_slack_MVAr', 'Aprobado'});
writecell({'Resumen de validación'}, archivo_resultados, 'Sheet', hoja_caso, ...
          'Range', 'A4', 'WriteMode', 'inplace');
writetable(resumen, archivo_resultados, 'Sheet', hoja_caso, ...
           'Range', 'A5', 'WriteMode', 'inplace');

configuracion = table(string(archivo_caso), string(mpver()), tol, tol_referencia, ...
    limite_ybus, limite_voltaje, limite_angulo, limite_potencia, ...
    false, logical(exito_mp), solucion_mp.et, limite_totales, "Caso base", ...
    'VariableNames', {'Archivo_caso', 'Version_MATPOWER', 'Tolerancia_metodos_pu', ...
    'Tolerancia_referencia_pu', 'Limite_Ybus_pu', 'Limite_V_pu', ...
    'Limite_angulo_grados', 'Limite_PQ_pu', 'Aplica_limites_Q', ...
    'Convergio_MATPOWER', 'Tiempo_total_MATPOWER_s', 'Limite_totales_MW_MVAr', 'Tipo_prueba'});
writetable(configuracion, archivo_resultados, 'Sheet', hoja_caso, ...
           'Range', 'A1', 'WriteMode', 'inplace');

fprintf('\nValidación del caso: %s\n', nombre_caso);
fprintf('Diferencia máxima de Ybus: %.3e pu\n', error_ybus);
disp(resumen);
disp(totales);
if all(aprobado)
    disp('Los tres métodos cumplen los criterios de validación configurados.');
else
    warning('Hay métodos que no cumplen los criterios. Revise el resumen de la hoja %s.', hoja_caso);
end
fprintf('Informe guardado en: %s (hoja %s)\n', archivo_resultados, hoja_caso);
end
