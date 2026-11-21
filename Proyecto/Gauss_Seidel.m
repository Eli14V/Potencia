function [tabla_resultados, converge, iter, error_max, tiempo] = ...
    Gauss_Seidel(datos_barras, datos_gen, datos_lineas, baseMVA, tol, max_iter)
%Nota: para los calculos se usa el metodo de Flat Start

% Medir la preparacion, las iteraciones y la evaluacion final del desbalance.
inicio_tiempo = tic;

%% Construcción de Ybus e identificación de barras
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

% Todos los ángulos parten iguales al ángulo de referencia de la Slack.
ang = deg2rad(datos_barras(idx_slack, 9))*ones(n, 1);
V = Vmag .* exp(1j*ang);

%% Iteraciones de Gauss-Seidel (núcleo reutilizado de Gaus_seidel.m)
iter = 0;

% Desbalance inicial, antes de realizar la primera actualización.
Scal = V .* conj(Ybus*V);
Pcal = real(Scal);
Qcal = imag(Scal);
error_pot = [Pesp(idx_ang) - Pcal(idx_ang);
             Qesp(idx_PQ) - Qcal(idx_PQ)];
error_max = max([0; abs(error_pot)]);

for paso = 1:max_iter
    if error_max < tol
        break;
    end

    for i = 1:n
        Vi_anterior = V(i);

        if tipo_barra(i) == 3
            % Barra Slack: no se actualiza.
            continue;
        elseif tipo_barra(i) == 1
            % Barra PQ: se conocen las potencias netas P y Q.
            Q_usar = Qesp(i);
        else
            % Barra PV: calcular su potencia reactiva neta con el voltaje actual.
            Q_usar = -imag(conj(Vi_anterior) * (Ybus(i,:) * V));
        end

        % El vector V ya contiene los voltajes actualizados de barras anteriores.
        suma = Ybus(i,:) * V - Ybus(i,i)*Vi_anterior;
        V_temp = ((Pesp(i) - 1j*Q_usar)/conj(Vi_anterior) ...
                  - suma)/Ybus(i,i);

        if tipo_barra(i) == 2
            % Conservar la magnitud especificada de la barra PV.
            V(i) = Vmag(i)*V_temp/abs(V_temp);
        else
            V(i) = V_temp;
        end
    end

    iter = iter + 1;

    % Evaluar la convergencia mediante desbalances de potencia, igual que Newton.
    Scal = V .* conj(Ybus*V);
    Pcal = real(Scal);
    Qcal = imag(Scal);
    error_pot = [Pesp(idx_ang) - Pcal(idx_ang);
                 Qesp(idx_PQ) - Qcal(idx_PQ)];
    error_max = max([0; abs(error_pot)]);

    % Detener el cálculo si la iteración produce voltajes no finitos.
    if any(~isfinite(V))
        break;
    end
end

converge = all(isfinite(V)) && isfinite(error_max) && error_max < tol;
tiempo = toc(inicio_tiempo);

%% Resultados por barra, con las mismas columnas de Newton-Raphson
barra = id_barras;
tipo = tipo_barra;
V_pu = abs(V);
Angulo = rad2deg(angle(V));
P_neta = Pcal;
Q_neta = Qcal;
Convergio = repmat(converge, n, 1);
tabla_resultados = table(barra, tipo, V_pu, Angulo, P_neta, Q_neta, Convergio);
tabla_resultados.Properties.VariableNames = ...
    {'Barra', 'Tipo', 'V_pu', 'Angulo_grados', 'P_neta_pu', 'Q_neta_pu', 'Convergio'};
end
