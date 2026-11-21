function Ybus = construir_Ybus(datos_barras, datos_lineas, baseMVA)
n = size(datos_barras, 1);
id_barras = datos_barras(:, 1);

% Considerar solamente las ramas en servicio (columna 11).
lineas = datos_lineas(datos_lineas(:, 11) > 0, :);

% Relacionar los identificadores originales con las filas de datos_barras.
[~, barra_desde] = ismember(lineas(:, 1), id_barras);
[~, barra_hasta] = ismember(lineas(:, 2), id_barras);

Ybus = zeros(n);

for k = 1:size(lineas, 1)
    i = barra_desde(k);
    j = barra_hasta(k);
    m_R = lineas(k, 3);
    m_X = lineas(k, 4);
    m_b = lineas(k, 5);

    y = 1 / (m_R + 1j*m_X);
    yp = 1j*m_b/2;


    relacion = lineas(k, 9);
    if relacion == 0
        relacion = 1;
    end
    desfase = deg2rad(lineas(k, 10));
    tap = relacion * exp(1j*desfase);

    Ybus(i,i) = Ybus(i,i) + (y + yp)/(tap*conj(tap));
    Ybus(j,j) = Ybus(j,j) + y + yp;
    Ybus(i,j) = Ybus(i,j) - y/conj(tap);
    Ybus(j,i) = Ybus(j,i) - y/tap;
end

% Gs y Bs están en las columnas 5 y 6 de Barras, sobre la base en MVA.
for i = 1:n
    Ybus(i,i) = Ybus(i,i) + ...
        (datos_barras(i, 5) + 1j*datos_barras(i, 6))/baseMVA;
end
end
