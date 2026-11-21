function [tabla_resultados, converge, iter, error_max, tiempo] = ...
    Desacoplado_Rapido(datos_barras, datos_gen, datos_lineas, baseMVA, tol, max_iter)

% Medir la preparacion, las iteraciones y la evaluacion final del desbalance.
inicio_tiempo = tic;

%% Construcción de Ybus e identificación de barras
% La Ybus original se conserva para calcular las potencias reales del modelo.
Ybus = construir_Ybus(datos_barras, datos_lineas, baseMVA);
n = size(datos_barras, 1);
id_barras = datos_barras(:, 1);
tipo_barra = datos_barras(:, 2);

idx_PQ = find(tipo_barra == 1);
idx_PV = find(tipo_barra == 2);
idx_slack = find(tipo_barra == 3);
idx_ang = [idx_PV; idx_PQ];

%% Potencias especificadas: generación menos demanda, en pu
generadores = datos_gen(datos_gen(:, 8) > 0, :);
[~, barra_gen] = ismember(generadores(:, 1), id_barras);

PG = zeros(n, 1);
QG = zeros(n, 1);
for k = 1:size(generadores, 1)
    i = barra_gen(k);
    PG(i) = PG(i) + generadores(k, 2)/baseMVA;
    QG(i) = QG(i) + generadores(k, 3)/baseMVA;
end

PD = datos_barras(:, 3)/baseMVA;
QD = datos_barras(:, 4)/baseMVA;
Pesp = PG - PD;
Qesp = QG - QD;

%% Voltajes iniciales: Flat Start
Vmag = ones(n, 1);
idx_control = [idx_PV; idx_slack];
for k = 1:numel(idx_control)
    i = idx_control(k);
    voltajes = generadores(barra_gen == i, 6);
    Vmag(i) = voltajes(1);
end

ang = deg2rad(datos_barras(idx_slack, 9))*ones(n, 1);
V = Vmag .* exp(1j*ang);

%% Matrices constantes Bprima y Bsegunda

%% Bprima
% Se modifican copias; los datos originales y Ybus permanecen completos.
barras_prima = datos_barras;
lineas_prima = datos_lineas;
barras_prima(:, 6) = 0;  % Bs de las barras
lineas_prima(:, 3) = 0;  % Resistencias
lineas_prima(:, 5) = 0;  % Susceptancias de carga de las líneas
lineas_prima(:, 9) = 1;  % Relaciones de tap unitarias
Bprima = -imag(construir_Ybus(barras_prima, lineas_prima, baseMVA));
Bprima = Bprima(idx_ang, idx_ang);

%% Bsegunda
lineas_segunda = datos_lineas;
lineas_segunda(:, 10) = 0;
Bsegunda = -imag(construir_Ybus(datos_barras, lineas_segunda, baseMVA));
Bsegunda = Bsegunda(idx_PQ, idx_PQ);

% LU descompone otra matriz de forma P*A=L*U
% Pprima*Bprima = Lprima*Uprima, y lo mismo para Bsegunda.
[Lprima, Uprima, Pprima] = lu(Bprima);
[Lsegunda, Usegunda, Psegunda] = lu(Bsegunda);

%% Desbalances iniciales de potencia
Scal = V .* conj(Ybus*V);
Pcal = real(Scal);
Qcal = imag(Scal);
error_pot = [Pesp(idx_ang) - Pcal(idx_ang);
             Qesp(idx_PQ) - Qcal(idx_PQ)];
error_max = max([0; abs(error_pot)]);
iter = 0;

%% Iteraciones del desacoplado rápido
for paso = 1:max_iter
    if error_max < tol
        break;
    end

    %% Paso de correcciones de magnitudes DeltaBprima
    delta_P = (Pesp(idx_ang) - Pcal(idx_ang)) ./ Vmag(idx_ang);
    delta_ang = Uprima \ (Lprima \ (Pprima*delta_P));
    ang(idx_ang) = ang(idx_ang) + delta_ang;
    V = Vmag .* exp(1j*ang);
    iter = iter + 1;

    %% Recalcular potencias con los ángulos nuevos antes del paso reactivo.
    Scal = V .* conj(Ybus*V);
    Pcal = real(Scal);
    Qcal = imag(Scal);
    error_pot = [Pesp(idx_ang) - Pcal(idx_ang);
                 Qesp(idx_PQ) - Qcal(idx_PQ)];
    error_max = max([0; abs(error_pot)]);

    % Si ya convergió después de corregir ángulos, terminar aquí.
    if error_max < tol || any(~isfinite(V))
        break;
    end

    %% Paso correcciones de Bsegunda
    delta_Q = (Qesp(idx_PQ) - Qcal(idx_PQ)) ./ Vmag(idx_PQ);
    delta_V = Usegunda \ (Lsegunda \ (Psegunda*delta_Q));
    V_nueva = Vmag(idx_PQ) + delta_V;

    %% Detener una iteración si hay error
    if any(V_nueva <= 0) || any(~isfinite(V_nueva))
        break;
    end
    Vmag(idx_PQ) = V_nueva;
    V = Vmag .* exp(1j*ang);

    %% Convergencias
    Scal = V .* conj(Ybus*V);
    Pcal = real(Scal);
    Qcal = imag(Scal);
    error_pot = [Pesp(idx_ang) - Pcal(idx_ang);
                 Qesp(idx_PQ) - Qcal(idx_PQ)];
    error_max = max([0; abs(error_pot)]);
end

converge = all(isfinite(V)) && isfinite(error_max) && error_max < tol;
tiempo = toc(inicio_tiempo);

%% Resultados por barra
barra = id_barras;
tipo = tipo_barra;
V_pu = Vmag;
Angulo = rad2deg(ang);
P_neta = Pcal;
Q_neta = Qcal;
Convergio = repmat(converge, n, 1);
tabla_resultados = table(barra, tipo, V_pu, Angulo, P_neta, Q_neta, Convergio);
tabla_resultados.Properties.VariableNames = ...
    {'Barra', 'Tipo', 'V_pu', 'Angulo_grados', 'P_neta_pu', 'Q_neta_pu', 'Convergio'};
end
