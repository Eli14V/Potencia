function [tabla_lineas, resumen_sistema, tabla_slack, ...
          menores_tensiones, mayores_flujos] = ...
    calcular_resultados(datos_barras, datos_lineas, baseMVA, tabla_resultados)
% Calcula resultados adicionales con los voltajes obtenidos por cualquier metodo.

%% Recuperar los voltajes en el orden de las barras del archivo de entrada
id_barras = datos_barras(:, 1);
[~, orden] = ismember(id_barras, tabla_resultados.Barra);
resultados = tabla_resultados(orden, :);

%se obtiene el fasor del voltaje
V = resultados.V_pu .* exp(1j*deg2rad(resultados.Angulo_grados));
converge = all(resultados.Convergio);

%% Se identifican desde donde hasta que otro punto va la barra.
num_lineas = size(datos_lineas, 1);
[~, barra_desde] = ismember(datos_lineas(:, 1), id_barras);
[~, barra_hasta] = ismember(datos_lineas(:, 2), id_barras);

% Se crea vector para los valores de potencia aparente
S_desde = complex(zeros(num_lineas, 1));
S_hasta = complex(zeros(num_lineas, 1));

% Se crea vector para los valores de potencia reactiva
Q_perdida_serie = zeros(num_lineas, 1);
Q_carga_linea = zeros(num_lineas, 1);


for k = 1:num_lineas
    % Una rama desconectada conserva su fila y tiene todos sus flujos en cero.
    if datos_lineas(k, 11) == 0
        continue;
    end

    i = barra_desde(k);
    j = barra_hasta(k);
    R = datos_lineas(k, 3);
    X = datos_lineas(k, 4);
    b = datos_lineas(k, 5);
    y = 1/(R + 1j*X);
    yp = 1j*b/2;

    relacion = datos_lineas(k, 9);
    if relacion == 0
        relacion = 1;
    end

    %valor de tap del trasnformador mediante su magnitud y su desfase en pu
    tap = relacion*exp(1j*deg2rad(datos_lineas(k, 10)));

    % Corrientes que entran a la rama desde cada extremo tomando en cuenta el trasnformador.
    I_desde = (y + yp)/(tap*conj(tap))*V(i) - y/conj(tap)*V(j);
    I_hasta = -y/tap*V(i) + (y + yp)*V(j);


    S_desde(k) = baseMVA*V(i)*conj(I_desde);
    S_hasta(k) = baseMVA*V(j)*conj(I_hasta);

    % Separar el consumo reactivo serie del aporte de carga capacitiva.
    perdida_serie = baseMVA*abs(V(i)/tap - V(j))^2*conj(y);
    Q_perdida_serie(k) = imag(perdida_serie);
    Q_carga_linea(k) = baseMVA*b/2*(abs(V(i)/tap)^2 + abs(V(j))^2);
end

% P y Q positivos indican potencia desde la barra hacia la rama.
% La suma de ambos extremos representa lo absorbido por la rama completa.
% Q_neta = Q_perdida_serie - Q_carga_linea; puede resultar negativa.
P_perdida = real(S_desde + S_hasta);
Q_neta = imag(S_desde + S_hasta);
S_max = max(abs(S_desde), abs(S_hasta));

tabla_lineas = table((1:num_lineas)', datos_lineas(:, 1), datos_lineas(:, 2), ...
    datos_lineas(:, 11), real(S_desde), imag(S_desde), abs(S_desde), ...
    real(S_hasta), imag(S_hasta), abs(S_hasta), S_max, P_perdida, ...
    Q_perdida_serie, Q_carga_linea, Q_neta, repmat(converge, num_lineas, 1), ...
    'VariableNames', {'Rama', 'Desde', 'Hasta', 'Estado', ...
    'P_desde_MW', 'Q_desde_MVAr', 'S_desde_MVA', ...
    'P_hasta_MW', 'Q_hasta_MVAr', 'S_hasta_MVA', 'S_max_MVA', ...
    'P_perdida_MW', 'Q_perdida_serie_MVAr', 'Q_carga_linea_MVAr', ...
    'Q_neta_MVAr', 'Convergio'});

%% Generacion de la Slack: inyeccion neta mas demanda local
idx_slack = find(datos_barras(:, 2) == 3);
P_slack = baseMVA*resultados.P_neta_pu(idx_slack) + datos_barras(idx_slack, 3);
Q_slack = baseMVA*resultados.Q_neta_pu(idx_slack) + datos_barras(idx_slack, 4);

% Si hay varios generadores en la Slack, se presenta su generacion conjunta.
tabla_slack = table(id_barras(idx_slack), resultados.V_pu(idx_slack), ...
    resultados.Angulo_grados(idx_slack), P_slack, Q_slack, ...
    repmat(converge, numel(idx_slack), 1), ...
    'VariableNames', {'Barra', 'V_pu', 'Angulo_grados', ...
    'P_generacion_MW', 'Q_generacion_MVAr', 'Convergio'});

%% Resumen de tensiones y totales del sistema
[V_min, idx_min] = min(resultados.V_pu);
[V_max, idx_max] = max(resultados.V_pu);
fuera_rango = resultados.V_pu < 0.95 | resultados.V_pu > 1.05;

% Los shunts de barras se informan aparte de las perdidas de las ramas.
% Q_shunts es negativa para capacitores (Bs positiva) y positiva para reactores.
P_shunts = sum(datos_barras(:, 5).*abs(V).^2);
Q_shunts = -sum(datos_barras(:, 6).*abs(V).^2);

Magnitud = {'Numero de barras'; 'Ramas en servicio'; ...
    'Demanda activa total'; 'Demanda reactiva total'; ...
    'Perdidas activas en ramas'; 'Perdidas reactivas serie'; ...
    'Aporte reactivo de carga de lineas'; 'Absorcion reactiva neta de ramas'; ...
    'Consumo activo de shunts de barras'; 'Absorcion reactiva de shunts de barras'; ...
    'Tension minima'; 'Barra de tension minima'; ...
    'Tension maxima'; 'Barra de tension maxima'; ...
    'Barras fuera de 0.95 a 1.05 pu'; 'Generacion activa Slack'; ...
    'Generacion reactiva Slack'};

    
% nnz cuenta cuantos elementos cumplen una condicion.
Valor = [size(datos_barras, 1); nnz(datos_lineas(:, 11) > 0); ...
    sum(datos_barras(:, 3)); sum(datos_barras(:, 4)); ...
    sum(P_perdida); sum(Q_perdida_serie); sum(Q_carga_linea); sum(Q_neta); ...
    P_shunts; Q_shunts; V_min; id_barras(idx_min); V_max; id_barras(idx_max); ...
    nnz(fuera_rango); sum(P_slack); sum(Q_slack)];
Unidad = {'barras'; 'ramas'; 'MW'; 'MVAr'; 'MW'; 'MVAr'; 'MVAr'; 'MVAr'; ...
    'MW'; 'MVAr'; 'pu'; 'numero'; 'pu'; 'numero'; 'barras'; 'MW'; 'MVAr'};
resumen_sistema = table(Magnitud, Valor, Unidad, ...
    repmat(converge, numel(Valor), 1), ...
    'VariableNames', {'Magnitud', 'Valor', 'Unidad', 'Convergio'});

%% Cinco barras de menor tension y cinco ramas de mayor flujo aparente
menores_tensiones = sortrows(resultados, 'V_pu', 'ascend');
menores_tensiones = menores_tensiones(1:min(5, height(menores_tensiones)), :);

mayores_flujos = tabla_lineas(tabla_lineas.Estado > 0, :);
mayores_flujos = sortrows(mayores_flujos, 'S_max_MVA', 'descend');
mayores_flujos = mayores_flujos(1:min(5, height(mayores_flujos)), :);
end
