/* Dashboard de reportes: consume los endpoints de /api/reports (solo lectura)
   y dibuja KPIs, gráficos Chart.js y tablas. Nunca modifica datos.

   Reglas:
   - fetch con credentials: "same-origin" (cookies de sesión de Flask-Login).
   - 401 -> "Debe iniciar sesión" con enlace a /login.
   - 403 -> "No tiene permisos para ver reportes".
   - 400 -> se muestra el error devuelto por la API.
   - Listas vacías -> "Sin datos", sin romper los gráficos.
   - Los gráficos se destruyen antes de recrearse al aplicar filtros. */

(function () {
    "use strict";

    const $ = (id) => document.getElementById(id);

    // ------------------------------------------------------------------
    // Paleta sobria: azul oscuro, gris, blanco y acento dorado suave
    // ------------------------------------------------------------------
    const PALETTE = {
        blue: "#206bc4",
        darkBlue: "#1d3d5f",
        gold: "#d9a521",
        gray: "#8a97a6",
        mutedRed: "#c25454",
        blueSoft: "rgba(32, 108, 196, 0.15)",
        goldSoft: "rgba(217, 165, 33, 0.15)",
    };
    const DOUGHNUT_COLORS = [
        PALETTE.blue, PALETTE.gold, PALETTE.gray, PALETTE.darkBlue,
        "#5b8fc9", "#c9b06b", "#adb5bd", "#3d6d9e",
    ];

    // ------------------------------------------------------------------
    // Formateadores
    // ------------------------------------------------------------------
    const moneyFormat = new Intl.NumberFormat("es-VE", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
    const intFormat = new Intl.NumberFormat("es-VE");

    function fmtMoney(value) {
        return moneyFormat.format(Number(value || 0));
    }

    function fmtInt(value) {
        return intFormat.format(Number(value || 0));
    }

    function fmtQty(value) {
        const number = Number(value || 0);
        return Number.isInteger(number) ? intFormat.format(number) : moneyFormat.format(number);
    }

    /* 'YYYY-MM-DD' -> 'DD/MM/YYYY' sin usar Date (evita desfases de zona horaria). */
    function fmtDate(value) {
        if (!value) return "Sin datos";
        const parts = String(value).split("T")[0].split("-");
        if (parts.length !== 3) return String(value);
        return `${parts[2]}/${parts[1]}/${parts[0]}`;
    }

    /* ISO datetime (UTC naive del backend) -> fecha y hora local legible. */
    function fmtDateTime(value) {
        if (!value) return "Sin datos";
        const iso = String(value);
        const date = new Date(iso.endsWith("Z") || iso.includes("+") ? iso : iso + "Z");
        if (isNaN(date.getTime())) return "Sin datos";
        return date.toLocaleString("es-VE", {
            day: "2-digit", month: "2-digit", year: "numeric",
            hour: "2-digit", minute: "2-digit",
        });
    }

    function shortLabel(text, max = 18) {
        const value = String(text || "");
        return value.length > max ? value.slice(0, max - 1) + "…" : value;
    }

    // ------------------------------------------------------------------
    // Helper de API
    // ------------------------------------------------------------------
    class ApiError extends Error {
        constructor(status, message) {
            super(message);
            this.status = status;
        }
    }

    async function apiFetch(path, params = {}) {
        const url = new URL(path, window.location.origin);
        Object.entries(params).forEach(([key, value]) => {
            if (value !== null && value !== undefined && String(value).trim() !== "") {
                url.searchParams.set(key, String(value).trim());
            }
        });

        let response;
        try {
            response = await fetch(url, { credentials: "same-origin" });
        } catch (error) {
            throw new ApiError(0, "Error de conexión con el servidor.");
        }

        let data = {};
        try {
            data = await response.json();
        } catch (error) {
            // Respuesta sin cuerpo JSON: se deja data vacío.
        }
        if (!response.ok) {
            throw new ApiError(response.status, data.error || `Error HTTP ${response.status}.`);
        }
        return data;
    }

    // ------------------------------------------------------------------
    // Mensajes globales y por widget
    // ------------------------------------------------------------------
    let authAlertShown = false;

    function resetGlobalAlert() {
        authAlertShown = false;
        const box = $("global-alert");
        box.className = "alert d-none";
        box.innerHTML = "";
    }

    function showGlobalAlert(kind, html) {
        const box = $("global-alert");
        box.className = `alert alert-${kind}`;
        box.innerHTML = html;
    }

    /* Traduce el error a un mensaje corto para el widget y, si es de
       autenticación/permisos, muestra además el aviso global una sola vez. */
    function errorMessage(error) {
        if (error.status === 401) {
            if (!authAlertShown) {
                authAlertShown = true;
                showGlobalAlert(
                    "warning",
                    'Debe iniciar sesión para ver los reportes. ' +
                    '<a href="/login" class="alert-link">Ir al login</a>'
                );
            }
            return "Debe iniciar sesión.";
        }
        if (error.status === 403) {
            if (!authAlertShown) {
                authAlertShown = true;
                showGlobalAlert("danger", "No tiene permisos para ver reportes.");
            }
            return "No tiene permisos para ver reportes.";
        }
        return error.message || "No fue posible cargar este reporte.";
    }

    // ------------------------------------------------------------------
    // Gráficos (registro + destrucción antes de recrear)
    // ------------------------------------------------------------------
    const charts = {};

    function destroyChart(canvasId) {
        if (charts[canvasId]) {
            charts[canvasId].destroy();
            delete charts[canvasId];
        }
    }

    function showChartMessage(canvasId, message) {
        destroyChart(canvasId);
        $(canvasId).closest(".chart-holder").classList.add("d-none");
        const msg = $(canvasId + "-msg");
        msg.textContent = message;
        msg.classList.remove("d-none");
    }

    function renderChart(canvasId, config) {
        destroyChart(canvasId);
        $(canvasId).closest(".chart-holder").classList.remove("d-none");
        $(canvasId + "-msg").classList.add("d-none");
        charts[canvasId] = new Chart($(canvasId), config);
    }

    const GRID = { color: "rgba(138, 151, 166, 0.15)" };
    const LEGEND = { labels: { boxWidth: 12, usePointStyle: true } };

    // ------------------------------------------------------------------
    // Tablas
    // ------------------------------------------------------------------
    function badge(text, cls) {
        const span = document.createElement("span");
        span.className = `badge ${cls}`;
        span.textContent = text;
        return span;
    }

    /* Construye filas con textContent / nodos DOM (nunca HTML crudo). */
    function renderTableRows(tbodyId, items, columns) {
        const tbody = $(tbodyId);
        tbody.innerHTML = "";
        if (!items || !items.length) {
            const tr = document.createElement("tr");
            const td = document.createElement("td");
            td.colSpan = columns.length;
            td.className = "text-center text-secondary py-4";
            td.textContent = "Sin datos";
            tr.appendChild(td);
            tbody.appendChild(tr);
            return;
        }
        items.forEach((item) => {
            const tr = document.createElement("tr");
            columns.forEach((column) => {
                const td = document.createElement("td");
                if (column.className) td.className = column.className;
                const content = column.render(item);
                if (content instanceof Node) {
                    td.appendChild(content);
                } else {
                    td.textContent = content;
                }
                tr.appendChild(td);
            });
            tbody.appendChild(tr);
        });
    }

    function showTableError(tbodyId, columnsCount, message) {
        const tbody = $(tbodyId);
        tbody.innerHTML = "";
        const tr = document.createElement("tr");
        const td = document.createElement("td");
        td.colSpan = columnsCount;
        td.className = "text-center text-danger py-4";
        td.textContent = message;
        tr.appendChild(td);
        tbody.appendChild(tr);
    }

    function setBadgeCount(id, count) {
        $(id).textContent = `${fmtInt(count)} registro${count === 1 ? "" : "s"}`;
    }

    // ------------------------------------------------------------------
    // KPIs (GET /api/reports/dashboard-summary)
    // ------------------------------------------------------------------
    const KPI_IDS = [
        "kpi-total-products", "kpi-active-products", "kpi-inactive-products",
        "kpi-low-stock", "kpi-total-categories", "kpi-total-movements",
        "kpi-issued-notes", "kpi-cancelled-notes", "kpi-total-amount", "kpi-avg-amount",
    ];

    async function loadKpis() {
        try {
            const data = await apiFetch("/api/reports/dashboard-summary");
            $("kpi-total-products").textContent = fmtInt(data.total_products);
            $("kpi-active-products").textContent = fmtInt(data.active_products);
            $("kpi-inactive-products").textContent = fmtInt(data.inactive_products);
            $("kpi-low-stock").textContent = fmtInt(data.low_stock_products);
            $("kpi-total-categories").textContent = fmtInt(data.total_categories);
            $("kpi-total-movements").textContent = fmtInt(data.total_inventory_movements);
            $("kpi-issued-notes").textContent = fmtInt(data.issued_delivery_notes);
            $("kpi-cancelled-notes").textContent = fmtInt(data.cancelled_delivery_notes);
            $("kpi-total-amount").textContent = fmtMoney(data.total_amount_issued_delivery_notes);
            $("kpi-avg-amount").textContent = fmtMoney(data.average_amount_issued_delivery_notes);
        } catch (error) {
            KPI_IDS.forEach((id) => { $(id).textContent = "—"; });
            const message = errorMessage(error);
            if (!authAlertShown) showGlobalAlert("danger", message);
        }
    }

    // ------------------------------------------------------------------
    // Gráfico A: entradas vs salidas (línea)
    // ------------------------------------------------------------------
    async function loadEntriesExits(filters) {
        const canvas = "chart-entries-exits";
        try {
            const data = await apiFetch("/api/reports/entries-vs-exits", {
                date_from: filters.date_from, date_to: filters.date_to,
            });
            const items = data.items || [];
            if (!items.length) return showChartMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "line",
                data: {
                    labels: items.map((i) => fmtDate(i.date)),
                    datasets: [
                        {
                            label: "Entradas",
                            data: items.map((i) => i.total_entries_quantity),
                            borderColor: PALETTE.blue,
                            backgroundColor: PALETTE.blueSoft,
                            fill: true, tension: 0.3, pointRadius: 3,
                        },
                        {
                            label: "Salidas",
                            data: items.map((i) => i.total_exits_quantity),
                            borderColor: PALETTE.gold,
                            backgroundColor: PALETTE.goldSoft,
                            fill: true, tension: 0.3, pointRadius: 3,
                        },
                    ],
                },
                options: {
                    responsive: true, maintainAspectRatio: false,
                    plugins: { legend: LEGEND },
                    scales: {
                        y: { beginAtZero: true, ticks: { precision: 0 }, grid: GRID },
                        x: { grid: { display: false } },
                    },
                },
            });
        } catch (error) {
            showChartMessage(canvas, errorMessage(error));
        }
    }

    // ------------------------------------------------------------------
    // Gráfico B: stock actual vs mínimo (barras horizontales agrupadas)
    // ------------------------------------------------------------------
    async function loadStockMinimum() {
        const canvas = "chart-stock-minimum";
        try {
            const data = await apiFetch("/api/reports/stock-vs-minimum");
            // El servicio ordena por criticidad; se muestran hasta 20 productos.
            const items = (data.items || []).slice(0, 20);
            if (!items.length) return showChartMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "bar",
                data: {
                    labels: items.map((i) => shortLabel(i.name)),
                    datasets: [
                        { label: "Stock actual", data: items.map((i) => i.current_stock), backgroundColor: PALETTE.blue },
                        { label: "Stock mínimo", data: items.map((i) => i.minimum_stock), backgroundColor: PALETTE.gray },
                    ],
                },
                options: {
                    indexAxis: "y",
                    responsive: true, maintainAspectRatio: false,
                    plugins: {
                        legend: LEGEND,
                        tooltip: {
                            callbacks: {
                                title: (ctx) => items[ctx[0].dataIndex].name,
                            },
                        },
                    },
                    scales: {
                        x: { beginAtZero: true, ticks: { precision: 0 }, grid: GRID },
                        y: { grid: { display: false } },
                    },
                },
            });
        } catch (error) {
            showChartMessage(canvas, errorMessage(error));
        }
    }

    // ------------------------------------------------------------------
    // Gráfico C: productos con más salidas (barras verticales)
    // ------------------------------------------------------------------
    async function loadTopExits(filters) {
        const canvas = "chart-top-exits";
        try {
            const data = await apiFetch("/api/reports/top-products-by-exits", {
                date_from: filters.date_from, date_to: filters.date_to, limit: filters.limit,
            });
            const items = data.items || [];
            if (!items.length) return showChartMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "bar",
                data: {
                    labels: items.map((i) => shortLabel(i.product_name)),
                    datasets: [{
                        label: "Unidades salidas",
                        data: items.map((i) => i.total_quantity),
                        backgroundColor: PALETTE.blue,
                        borderRadius: 4,
                    }],
                },
                options: {
                    responsive: true, maintainAspectRatio: false,
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            callbacks: {
                                title: (ctx) => items[ctx[0].dataIndex].product_name,
                                label: (ctx) => {
                                    const item = items[ctx.dataIndex];
                                    return ` ${fmtInt(item.total_quantity)} unidades en ${fmtInt(item.total_movements)} movimientos`;
                                },
                            },
                        },
                    },
                    scales: {
                        y: { beginAtZero: true, ticks: { precision: 0 }, grid: GRID },
                        x: { grid: { display: false } },
                    },
                },
            });
        } catch (error) {
            showChartMessage(canvas, errorMessage(error));
        }
    }

    // ------------------------------------------------------------------
    // Gráfico D: notas de entrega por período (barras agrupadas)
    // ------------------------------------------------------------------
    async function loadNotesPeriod(filters) {
        const canvas = "chart-notes-period";
        try {
            const data = await apiFetch("/api/reports/delivery-notes-by-period", {
                date_from: filters.date_from, date_to: filters.date_to,
            });
            const items = data.items || [];
            if (!items.length) return showChartMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "bar",
                data: {
                    labels: items.map((i) => fmtDate(i.date)),
                    datasets: [
                        { label: "Emitidas", data: items.map((i) => i.issued_count), backgroundColor: PALETTE.blue, borderRadius: 4 },
                        { label: "Canceladas", data: items.map((i) => i.cancelled_count), backgroundColor: PALETTE.mutedRed, borderRadius: 4 },
                    ],
                },
                options: {
                    responsive: true, maintainAspectRatio: false,
                    plugins: {
                        legend: LEGEND,
                        tooltip: {
                            callbacks: {
                                footer: (ctx) => {
                                    const item = items[ctx[0].dataIndex];
                                    return `Monto emitido: ${fmtMoney(item.issued_amount)}`;
                                },
                            },
                        },
                    },
                    scales: {
                        y: { beginAtZero: true, ticks: { precision: 0 }, grid: GRID },
                        x: { grid: { display: false } },
                    },
                },
            });
        } catch (error) {
            showChartMessage(canvas, errorMessage(error));
        }
    }

    // ------------------------------------------------------------------
    // Gráfico E: productos más entregados (barras verticales)
    // ------------------------------------------------------------------
    async function loadTopDelivered(filters) {
        const canvas = "chart-top-delivered";
        try {
            const data = await apiFetch("/api/reports/top-delivered-products", {
                date_from: filters.date_from, date_to: filters.date_to, limit: filters.limit,
            });
            const items = data.items || [];
            if (!items.length) return showChartMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "bar",
                data: {
                    labels: items.map((i) => shortLabel(i.product_name)),
                    datasets: [{
                        label: "Unidades entregadas",
                        data: items.map((i) => i.total_quantity),
                        backgroundColor: PALETTE.gold,
                        borderRadius: 4,
                    }],
                },
                options: {
                    responsive: true, maintainAspectRatio: false,
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            callbacks: {
                                title: (ctx) => items[ctx[0].dataIndex].product_name,
                                label: (ctx) => {
                                    const item = items[ctx.dataIndex];
                                    return ` ${fmtQty(item.total_quantity)} unidades · ${fmtMoney(item.total_amount)} en ${fmtInt(item.notes_count)} notas`;
                                },
                            },
                        },
                    },
                    scales: {
                        y: { beginAtZero: true, ticks: { precision: 0 }, grid: GRID },
                        x: { grid: { display: false } },
                    },
                },
            });
        } catch (error) {
            showChartMessage(canvas, errorMessage(error));
        }
    }

    // ------------------------------------------------------------------
    // Gráfico F: notas por usuario (dona)
    // ------------------------------------------------------------------
    async function loadNotesUser(filters) {
        const canvas = "chart-notes-user";
        try {
            const data = await apiFetch("/api/reports/delivery-notes-by-user", {
                date_from: filters.date_from, date_to: filters.date_to,
            });
            const items = data.items || [];
            if (!items.length) return showChartMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "doughnut",
                data: {
                    labels: items.map((i) => shortLabel(i.user_name, 22)),
                    datasets: [{
                        data: items.map((i) => i.notes_count),
                        backgroundColor: items.map((_, idx) => DOUGHNUT_COLORS[idx % DOUGHNUT_COLORS.length]),
                        borderWidth: 1,
                    }],
                },
                options: {
                    responsive: true, maintainAspectRatio: false,
                    plugins: {
                        legend: { position: "right", labels: { boxWidth: 12, usePointStyle: true } },
                        tooltip: {
                            callbacks: {
                                label: (ctx) => {
                                    const item = items[ctx.dataIndex];
                                    return ` ${item.user_name}: ${fmtInt(item.notes_count)} notas · ${fmtMoney(item.total_amount)}`;
                                },
                            },
                        },
                    },
                },
            });
        } catch (error) {
            showChartMessage(canvas, errorMessage(error));
        }
    }

    // ------------------------------------------------------------------
    // Tabla 1: productos bajo stock
    // ------------------------------------------------------------------
    const LOW_STOCK_COLUMNS = [
        { render: (i) => i.code },
        { render: (i) => i.name },
        { render: (i) => i.category_name },
        { className: "text-end", render: (i) => fmtQty(i.current_stock) },
        { className: "text-end", render: (i) => fmtQty(i.minimum_stock) },
        {
            render: (i) => (Number(i.current_stock) <= 0
                ? badge("Agotado", "bg-red-lt")
                : badge("Bajo stock", "bg-warning-lt")),
        },
    ];

    async function loadLowStock() {
        try {
            const data = await apiFetch("/api/reports/low-stock-products");
            renderTableRows("table-low-stock", data.items, LOW_STOCK_COLUMNS);
            setBadgeCount("badge-low-stock", data.count || 0);
        } catch (error) {
            showTableError("table-low-stock", LOW_STOCK_COLUMNS.length, errorMessage(error));
            setBadgeCount("badge-low-stock", 0);
        }
    }

    // ------------------------------------------------------------------
    // Tabla 2: productos sin movimiento
    // ------------------------------------------------------------------
    const NO_MOVEMENT_COLUMNS = [
        { render: (i) => i.code },
        { render: (i) => i.name },
        { render: (i) => i.category_name },
        { className: "text-end", render: (i) => fmtQty(i.current_stock) },
        {
            render: (i) => (i.last_movement_at
                ? fmtDateTime(i.last_movement_at)
                : badge("Nunca", "bg-secondary-lt")),
        },
        { className: "text-end", render: (i) => fmtInt(i.days_without_movement) },
    ];

    async function loadNoMovement(filters) {
        try {
            const data = await apiFetch("/api/reports/products-without-movement", {
                days: filters.days,
            });
            renderTableRows("table-no-movement", data.items, NO_MOVEMENT_COLUMNS);
            setBadgeCount("badge-no-movement", data.count || 0);
        } catch (error) {
            showTableError("table-no-movement", NO_MOVEMENT_COLUMNS.length, errorMessage(error));
            setBadgeCount("badge-no-movement", 0);
        }
    }

    // ------------------------------------------------------------------
    // Tabla 3: productos con exceso de stock
    // ------------------------------------------------------------------
    const EXCESS_COLUMNS = [
        { render: (i) => i.code },
        { render: (i) => i.name },
        { render: (i) => i.category_name },
        { className: "text-end", render: (i) => fmtQty(i.current_stock) },
        { className: "text-end", render: (i) => fmtQty(i.minimum_stock) },
        { className: "text-end fw-bold", render: (i) => fmtQty(i.excess_quantity) },
    ];

    async function loadExcess(filters) {
        try {
            const data = await apiFetch("/api/reports/excess-stock-products", {
                multiplier: filters.multiplier,
            });
            renderTableRows("table-excess", data.items, EXCESS_COLUMNS);
            setBadgeCount("badge-excess", data.count || 0);
        } catch (error) {
            showTableError("table-excess", EXCESS_COLUMNS.length, errorMessage(error));
            setBadgeCount("badge-excess", 0);
        }
    }

    // ------------------------------------------------------------------
    // Tabla 4: ajustes de inventario
    // ------------------------------------------------------------------
    const ADJUSTMENT_COLUMNS = [
        { render: (i) => fmtDateTime(i.created_at) },
        { render: (i) => `${i.product_code} · ${i.product_name}` },
        { className: "text-end", render: (i) => fmtQty(i.previous_stock) },
        { className: "text-end fw-bold", render: (i) => fmtQty(i.new_stock) },
        { render: (i) => i.reason || "Sin datos" },
        {
            render: (i) => (i.user_name
                ? i.user_name
                : badge("Sin datos", "bg-secondary-lt")),
        },
    ];

    async function loadAdjustments(filters) {
        try {
            const data = await apiFetch("/api/reports/inventory-adjustments", {
                date_from: filters.date_from, date_to: filters.date_to,
            });
            renderTableRows("table-adjustments", data.items, ADJUSTMENT_COLUMNS);
            setBadgeCount("badge-adjustments", data.count || 0);
        } catch (error) {
            showTableError("table-adjustments", ADJUSTMENT_COLUMNS.length, errorMessage(error));
            setBadgeCount("badge-adjustments", 0);
        }
    }

    // ------------------------------------------------------------------
    // Filtros y carga general
    // ------------------------------------------------------------------
    function getFilters() {
        return {
            date_from: $("f-date-from").value,
            date_to: $("f-date-to").value,
            days: $("f-days").value,
            multiplier: $("f-multiplier").value,
            limit: $("f-limit").value,
        };
    }

    function validateFilters(filters) {
        const errorBox = $("filters-error");
        errorBox.classList.add("d-none");
        if (filters.date_from && filters.date_to && filters.date_from > filters.date_to) {
            errorBox.textContent = "El campo 'Desde' no puede ser mayor que 'Hasta'.";
            errorBox.classList.remove("d-none");
            return false;
        }
        return true;
    }

    async function loadAll() {
        const filters = getFilters();
        if (!validateFilters(filters)) return;

        resetGlobalAlert();
        const applyButton = $("btn-apply");
        applyButton.disabled = true;
        try {
            await Promise.allSettled([
                loadKpis(),
                loadEntriesExits(filters),
                loadStockMinimum(),
                loadTopExits(filters),
                loadNotesPeriod(filters),
                loadTopDelivered(filters),
                loadNotesUser(filters),
                loadLowStock(),
                loadNoMovement(filters),
                loadExcess(filters),
                loadAdjustments(filters),
            ]);
            $("last-update").textContent = "Actualizado: " + new Date().toLocaleString("es-VE", {
                day: "2-digit", month: "2-digit", year: "numeric",
                hour: "2-digit", minute: "2-digit",
            });
        } finally {
            applyButton.disabled = false;
        }
    }

    $("filters-form").addEventListener("submit", (event) => {
        event.preventDefault();
        loadAll();
    });

    $("btn-clear").addEventListener("click", () => {
        $("f-date-from").value = "";
        $("f-date-to").value = "";
        $("f-days").value = "30";
        $("f-multiplier").value = "3";
        $("f-limit").value = "10";
        loadAll();
    });

    loadAll();
})();
