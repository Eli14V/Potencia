function [tabla_resultados, converge, iter, error_max, tiempo] = ...
    Newton_Raphson(datos_barras, datos_gen, datos_lineas, baseMVA, tol, max_iter)
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
    % Sumar también si hay varios generadores en la misma barra.
    PG(i) = PG(i) + generadores(k, 2)/baseMVA;
    QG(i) = QG(i) + generadores(k, 3)/baseMVA;
end


PD = datos_barras(:, 3)/baseMVA;
QD = datos_barras(:, 4)/baseMVA;
Pesp = PG - PD;
Qesp = QG - QD;

%% Voltajes iniciales: Flat Start
V = ones(n, 1);

% Mantener el ángulo de referencia indicado en el caso.
% Todos los ángulos parten iguales al de la Slack.
ang = deg2rad(datos_barras(idx_slack, 9))*ones(n, 1);

% Las magnitudes de PV y Slack se toman de Vg en Generadores (columna 6).
idx_control = [idx_PV; idx_slack];
for k = 1:numel(idx_control)
    i = idx_control(k);
    voltajes = generadores(barra_gen == i, 6);
    V(i) = voltajes(1);
end

G = real(Ybus);
B = imag(Ybus);

%% Iteraciones de Newton-Raphson (núcleo reutilizado de quiz.m)
iter = 0;

for paso = 1:max_iter
    Vcal = V .* exp(1j*ang);
    Scal = Vcal .* conj(Ybus*Vcal);
    Pcal = real(Scal);
    Qcal = imag(Scal);

    delta_P = Pesp(idx_ang) - Pcal(idx_ang);
    delta_Q = Qesp(idx_PQ) - Qcal(idx_PQ);
    error_pot = [delta_P; delta_Q];
    error_max = max([0; abs(error_pot)]);

    if error_max < tol
        break;
    end

    % Jacobiano: mismas expresiones de H, N, M y L utilizadas en el quiz.
    H = zeros(n);
    N = zeros(n);
    M = zeros(n);
    L = zeros(n);

    for i = 1:n
        for j = 1:n
            diferencia = ang(i) - ang(j);

            if i == j
                H(i,i) = -Qcal(i) - B(i,i)*V(i)^2;
                N(i,i) = Pcal(i)/V(i) + G(i,i)*V(i);
                M(i,i) = Pcal(i) - G(i,i)*V(i)^2;
                L(i,i) = Qcal(i)/V(i) - B(i,i)*V(i);
            else
                H(i,j) = V(i)*V(j)*(G(i,j)*sin(diferencia) - B(i,j)*cos(diferencia));
                N(i,j) = V(i)*(G(i,j)*cos(diferencia) + B(i,j)*sin(diferencia));
                M(i,j) = -V(i)*V(j)*(G(i,j)*cos(diferencia) + B(i,j)*sin(diferencia));
                L(i,j) = V(i)*(G(i,j)*sin(diferencia) - B(i,j)*cos(diferencia));
            end
        end
    end

    J = [H(idx_ang,idx_ang), N(idx_ang,idx_PQ);
         M(idx_PQ,idx_ang), L(idx_PQ,idx_PQ)];

    % Una red sin referencia adecuada puede producir un jacobiano singular.
    if rcond(J) < eps
        warning('Newton:JacobianoSingular', 'El jacobiano es singular o está mal condicionado.');
        break;
    end
    correccion = J \ error_pot;
    if any(~isfinite(correccion))
        warning('Newton:CorreccionInvalida', 'La corrección contiene valores no finitos.');
        break;
    end

    n_ang = numel(idx_ang);
    V_nueva = V(idx_PQ) + correccion(n_ang+1:end);
    if any(V_nueva <= 0)
        warning('Newton:VoltajeInvalido', 'La corrección produce magnitudes no positivas.');
        break;
    end

    ang(idx_ang) = ang(idx_ang) + correccion(1:n_ang);
    V(idx_PQ) = V_nueva;
    iter = iter + 1;
end

%% Recalcular los desbalances con los últimos voltajes
Vc = V .* exp(1j*ang);
Scal = Vc .* conj(Ybus*Vc);
Pcal = real(Scal);
Qcal = imag(Scal);
error_pot = [Pesp(idx_ang) - Pcal(idx_ang);
             Qesp(idx_PQ) - Qcal(idx_PQ)];
error_max = max([0; abs(error_pot)]);
converge = isfinite(error_max) && error_max < tol;
tiempo = toc(inicio_tiempo);

%% Resultados por barra, conservando los identificadores originales
% P y Q son inyecciones NETAS en pu, no potencias individuales de generadores.
barra = id_barras;
tipo = tipo_barra;
V_pu = V;
Angulo = rad2deg(ang);
P_neta = Pcal;
Q_neta = Qcal;
Convergio = repmat(converge, n, 1);
tabla_resultados = table(barra, tipo, V_pu, Angulo, P_neta, Q_neta, Convergio);
tabla_resultados.Properties.VariableNames = ...
    {'Barra', 'Tipo', 'V_pu', 'Angulo_grados', 'P_neta_pu', 'Q_neta_pu', 'Convergio'};
end
