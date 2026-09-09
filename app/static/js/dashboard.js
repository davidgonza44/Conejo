/* Pantalla Inicio: dibuja KPIs, gráficos Chart.js, listas y tablas.

   Modo normal: consume /api/reports/* (solo lectura, cookies de sesión) y
   convierte cada respuesta a un modelo de vista.
   Modo de referencia visual (debug + ?ref=1): window.INICIO_REFERENCE trae
   el modelo ya formateado y no se llama a la API.

   Reglas:
   - 401 -> "Debe iniciar sesión" con enlace a /login; 403 -> sin permisos.
   - 400/red -> mensaje devuelto por la API dentro del widget.
   - Listas vacías -> "Sin datos", sin romper los gráficos.
   - Los gráficos se destruyen antes de recrearse al aplicar filtros. */

(function () {
    "use strict";

    const $ = (id) => document.getElementById(id);
    const REF = window.INICIO_REFERENCE || null;

    const COLORS = {
        blue: "#1a73e8", blueLight: "#8ab4f8", green: "#3fae62", orange: "#fdb429",
        purple: "#8e73e4", teal: "#20c2c5", gray: "#a6adb8", red: "#dc2626",
    };
    const DONUT = [COLORS.blue, COLORS.green, COLORS.orange, COLORS.purple, COLORS.teal, COLORS.gray, "#1d3d5f", "#d9a521"];
    const AXIS_FONT = { family: "Inter, 'Segoe UI', sans-serif", size: 10.5 };
    const AXIS_COLOR = "#6b7280";
    const GRID = { color: "#eef0f3" };

    // ------------------------------------------------------------------
    // Formateadores
    // ------------------------------------------------------------------
    const moneyFormat = new Intl.NumberFormat("es-VE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const intFormat = new Intl.NumberFormat("es-VE");
    const fmtMoney = (v) => moneyFormat.format(Number(v || 0));
    const fmtInt = (v) => intFormat.format(Number(v || 0));
    const fmtQty = (v) => (Number.isInteger(Number(v || 0)) ? fmtInt(v) : fmtMoney(v));

    /* 'YYYY-MM-DD' -> 'DD/MM/YYYY' sin usar Date (evita desfases de zona horaria). */
    function fmtDate(value) {
        if (!value) return "Sin datos";
        const parts = String(value).split("T")[0].split("-");
        return parts.length === 3 ? `${parts[2]}/${parts[1]}/${parts[0]}` : String(value);
    }

    /* ISO datetime (UTC naive del backend) -> fecha y hora local legible. */
    function fmtDateTime(value) {
        if (!value) return "Sin datos";
        const iso = String(value);
        const date = new Date(iso.endsWith("Z") || iso.includes("+") ? iso : iso + "Z");
        if (isNaN(date.getTime())) return "Sin datos";
        return date.toLocaleString("es-VE", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
    }

    function shortLabel(text, max = 18) {
        const value = String(text || "");
        return value.length > max ? value.slice(0, max - 1) + "…" : value;
    }

    // ------------------------------------------------------------------
    // API y mensajes
    // ------------------------------------------------------------------
    class ApiError extends Error {
        constructor(status, message) { super(message); this.status = status; }
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
        try { data = await response.json(); } catch (error) { /* sin cuerpo JSON */ }
        if (!response.ok) throw new ApiError(response.status, data.error || `Error HTTP ${response.status}.`);
        return data;
    }

    let authAlertShown = false;

    function showGlobalAlert(kind, html) {
        const box = $("global-alert");
        box.className = `alert alert-${kind}`;
        box.innerHTML = html;
    }

    /* Mensaje corto para el widget; el aviso global de sesión/permisos se muestra una sola vez. */
    function errorMessage(error) {
        if (error.status === 401) {
            if (!authAlertShown) {
                authAlertShown = true;
                showGlobalAlert("warning", 'Debe iniciar sesión para ver los reportes. <a href="/login" class="alert-link">Ir al login</a>');
            }
            return "Debe iniciar sesión.";
        }
        if (error.status === 403) {
            if (!authAlertShown) { authAlertShown = true; showGlobalAlert("danger", "No tiene permisos para ver reportes."); }
            return "No tiene permisos para ver reportes.";
        }
        return error.message || "No fue posible cargar este reporte.";
    }

    // ------------------------------------------------------------------
    // DOM y gráficos
    // ------------------------------------------------------------------
    function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }

    /* Iconos rellenos que la webfont de Tabler no incluye; se dibujan inline. */
    const SVG_ICONS = {
        cube: '<path d="M12 2.4 3.2 6.8v10.4L12 21.6l8.8-4.4V6.8z"/>'
            + '<path d="M3.2 6.8 12 11.2l8.8-4.4M12 11.2v10.4" fill="none" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/>',
        users: '<circle cx="9" cy="8" r="3.6"/><path d="M2.2 19.4c0-3.5 3-6.3 6.8-6.3s6.8 2.8 6.8 6.3v.6H2.2z"/>'
            + '<circle cx="17" cy="9" r="2.9"/><path d="M16.9 20c0-2.5-.9-4.7-2.5-6.3.8-.4 1.7-.6 2.6-.6 2.8 0 5 2.1 5 4.7V20z"/>',
        "alert-triangle": '<path d="M10.3 3.6 2.2 17.9A2 2 0 0 0 3.9 21h16.2a2 2 0 0 0 1.7-3.1L13.7 3.6a2 2 0 0 0-3.4 0z"/>'
            + '<path d="M12 9v5" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="17.2" r="1.1" fill="#fff"/>',
        cart: '<circle cx="9" cy="20" r="1.8"/><circle cx="17.5" cy="20" r="1.8"/>'
            + '<path d="M2 3h2.6l2.9 11.4a1.6 1.6 0 0 0 1.6 1.2h9.2a1.6 1.6 0 0 0 1.5-1.1L22 7H6.2" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>'
            + '<path d="M6.4 7.3h15l-1.8 7H8.2z"/>',
        clipboard: '<rect x="4.5" y="4" width="15" height="18" rx="2.2"/><rect x="8.5" y="2.2" width="7" height="4" rx="1.2" stroke="#fff" stroke-width="1.2"/>'
            + '<path d="M8.3 12h7.4M8.3 16h5" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round"/>',
        "chart-bar": '<rect x="3" y="12.5" width="4.8" height="8.5" rx="1.2"/><rect x="9.6" y="7.5" width="4.8" height="13.5" rx="1.2"/><rect x="16.2" y="3" width="4.8" height="18" rx="1.2"/>',
        screw: '<path d="M12 1.8 15 5l-3 3-3-3z"/><path d="M9.8 8.2h4.4v8.4L12 22.2l-2.2-5.6z"/>'
            + '<path d="M9.8 11.2h4.4M9.8 14h4.4" fill="none" stroke="#fff" stroke-width="1"/>',
    };

    function svgIcon(key) {
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        svg.setAttribute("viewBox", "0 0 24 24");
        svg.setAttribute("fill", "currentColor");
        svg.setAttribute("class", "ix-svg");
        svg.innerHTML = SVG_ICONS[key];
        return svg;
    }

    function icon(name, className) {
        const wrap = el("span", className);
        wrap.setAttribute("aria-hidden", "true");
        wrap.appendChild(name.startsWith("svg:") ? svgIcon(name.slice(4)) : el("i", `ti ${name}`));
        return wrap;
    }

    const charts = {};

    function destroyChart(canvasId) {
        if (charts[canvasId]) { charts[canvasId].destroy(); delete charts[canvasId]; }
    }

    /* Oculta el cuerpo del gráfico (y hermanos marcados) y muestra un mensaje. */
    function showCardMessage(canvasId, message, isError) {
        destroyChart(canvasId);
        const body = $(canvasId).closest(".ix-chart, .ix-category-body");
        body.classList.add("d-none");
        body.parentElement.querySelectorAll(".ix-chart-legend").forEach((n) => n.classList.add("d-none"));
        const msg = $(canvasId + "-msg");
        msg.textContent = message;
        msg.className = `ix-msg${isError ? " is-error" : ""}`;
    }

    function renderChart(canvasId, config) {
        destroyChart(canvasId);
        const body = $(canvasId).closest(".ix-chart, .ix-category-body");
        body.classList.remove("d-none");
        body.parentElement.querySelectorAll(".ix-chart-legend").forEach((n) => n.classList.remove("d-none"));
        $(canvasId + "-msg").classList.add("d-none");
        charts[canvasId] = new Chart($(canvasId), config);
        return charts[canvasId];
    }

    // ------------------------------------------------------------------
    // KPIs
    // ------------------------------------------------------------------
    function kpiCard(k) {
        const card = el("div", "ix-card ix-kpi");
        card.appendChild(icon(k.icon, `ix-kpi-icon tone-${k.tone}${k.solid ? " is-solid" : ""}`));
        const body = el("div", "ix-kpi-body");
        body.appendChild(el("div", "ix-kpi-label", k.label));
        const line = el("div", "ix-kpi-line");
        line.appendChild(el("span", "ix-kpi-value", k.value));
        if (k.trend) {
            const trend = el("span", `ix-trend${k.trendTone ? ` is-${k.trendTone}` : ""}`);
            trend.appendChild(el("i", "ti ti-arrow-up"));
            trend.appendChild(el("span", null, k.trend));
            line.appendChild(trend);
        }
        body.appendChild(line);
        body.appendChild(el("div", "ix-kpi-sub", k.sub));
        card.appendChild(body);
        card.title = `${k.label}: ${k.value}`;
        return card;
    }

    function renderKpis(list) {
        $("kpi-row").replaceChildren(...list.map(kpiCard));
    }

    function liveKpis(d) {
        const empty = !d;
        const v = (fn) => (empty ? "—" : fn());
        return [
            { icon: "ti-currency-dollar", tone: "blue", solid: true, label: "Monto emitido en notas",
              value: v(() => fmtMoney(d.total_amount_issued_delivery_notes)),
              sub: `Promedio por nota: ${v(() => fmtMoney(d.average_amount_issued_delivery_notes))}` },
            { icon: "svg:cube", tone: "green", label: "Productos activos", value: v(() => fmtInt(d.active_products)),
              sub: `${v(() => fmtInt(d.total_products))} totales · ${v(() => fmtInt(d.inactive_products))} inactivos · ${v(() => fmtInt(d.total_categories))} categorías` },
            { icon: "ti-file-check", tone: "purple", label: "Notas emitidas", value: v(() => fmtInt(d.issued_delivery_notes)),
              sub: `${v(() => fmtInt(d.cancelled_delivery_notes))} canceladas` },
            { icon: "svg:alert-triangle", tone: "orange", label: "Alertas de bajo stock", value: v(() => fmtInt(d.low_stock_products)),
              sub: `${v(() => fmtInt(d.total_inventory_movements))} movimientos registrados` },
        ];
    }

    async function loadKpis() {
        if (REF) return renderKpis(REF.kpis);
        try {
            renderKpis(liveKpis(await apiFetch("/api/reports/dashboard-summary")));
        } catch (error) {
            renderKpis(liveKpis(null));
            const message = errorMessage(error);
            if (!authAlertShown) showGlobalAlert("danger", message);
        }
    }

    // ------------------------------------------------------------------
    // Gráfico de líneas (ventas / entradas vs salidas)
    // ------------------------------------------------------------------
    function renderSalesLegend(series) {
        const legend = $("chart-sales-legend");
        legend.replaceChildren(...series.map((s) => {
            const li = el("li");
            li.appendChild(el("span", `ix-swatch${s.dashed ? " is-dashed" : ""}`));
            li.appendChild(el("span", null, s.label));
            return li;
        }));
    }

    function placeTooltip(chart, tip) {
        const box = $("chart-sales-tip");
        box.classList.remove("is-visible");
        if (!tip) return;
        const point = chart.getDatasetMeta(0).data[tip.index];
        if (!point) return;
        box.replaceChildren(el("span", null, tip.title), el("strong", null, tip.value));
        box.classList.add("is-visible");
        box.style.left = `${Math.round(point.x - box.offsetWidth + 6)}px`;
        box.style.top = `${Math.round(point.y + 18)}px`;
    }

    function renderSales(model) {
        renderSalesLegend(model.series);
        const tipIndex = model.tooltip ? model.tooltip.index : -1;
        const datasets = model.series.map((s, i) => {
            const color = s.dashed ? COLORS.blueLight : COLORS.blue;
            return {
                label: s.label, data: s.data, borderColor: color,
                backgroundColor: s.dashed ? color : "rgba(26, 115, 232, 0.05)", fill: !s.dashed,
                borderWidth: 2.5, borderDash: s.dashed ? [5, 5] : [], tension: 0,
                pointRadius: s.data.map((_, idx) => (i === 0 && idx === tipIndex ? 5 : 4)),
                pointBorderWidth: s.data.map((_, idx) => (i === 0 && idx === tipIndex ? 4 : 0)),
                pointBorderColor: "rgba(26, 115, 232, 0.25)",
                pointBackgroundColor: color,
            };
        });
        const yTicks = { color: AXIS_COLOR, font: AXIS_FONT, padding: 8, precision: 0 };
        if (model.tickSuffix) {
            yTicks.stepSize = model.yStep;
            yTicks.callback = (v) => (v === 0 ? "0" : `${v / 1000}${model.tickSuffix}`);
        }
        renderChart("chart-sales", {
            type: "line",
            /* Recoloca la etiqueta flotante tras cada render (incluye redimensionar). */
            plugins: [{ id: "ixTip", afterRender: (chart) => placeTooltip(chart, model.tooltip) }],
            data: { labels: model.labels, datasets },
            options: {
                responsive: true, maintainAspectRatio: false, animation: false,
                layout: { padding: { top: 8, right: 14, left: 4 } },
                plugins: { legend: { display: false }, tooltip: { enabled: tipIndex < 0 } },
                scales: {
                    y: { beginAtZero: true, max: model.yMax, ticks: yTicks, grid: GRID, border: { display: false } },
                    x: { grid: { display: false }, border: { display: false }, ticks: { color: AXIS_COLOR, font: AXIS_FONT, padding: 10 } },
                },
            },
        });
    }

    async function loadSales(filters) {
        if (REF) return renderSales(REF.sales);
        try {
            const data = await apiFetch("/api/reports/entries-vs-exits", { date_from: filters.date_from, date_to: filters.date_to });
            const items = data.items || [];
            if (!items.length) return showCardMessage("chart-sales", "Sin datos");
            renderSales({
                labels: items.map((i) => fmtDate(i.date)),
                series: [
                    { label: "Entradas", data: items.map((i) => i.total_entries_quantity) },
                    { label: "Salidas", data: items.map((i) => i.total_exits_quantity), dashed: true },
                ],
            });
        } catch (error) {
            showCardMessage("chart-sales", errorMessage(error), true);
        }
    }

    // ------------------------------------------------------------------
    // Dona por categoría
    // ------------------------------------------------------------------
    function renderCategory(model) {
        renderChart("chart-category", {
            type: "doughnut",
            data: {
                labels: model.items.map((i) => i.label),
                datasets: [{
                    data: model.items.map((i) => i.value),
                    backgroundColor: model.items.map((_, idx) => DONUT[idx % DONUT.length]),
                    borderWidth: 2, borderColor: "#ffffff",
                }],
            },
            options: {
                responsive: true, maintainAspectRatio: false, animation: false, cutout: "54%",
                layout: { padding: 8 },
                plugins: { legend: { display: false } },
            },
        });
        $("chart-category-value").textContent = model.centerValue;
        $("chart-category-label").textContent = model.centerLabel;
        $("chart-category-legend").replaceChildren(...model.items.map((item, idx) => {
            const li = el("li");
            const dot = el("span", "ix-legend-dot");
            dot.style.background = DONUT[idx % DONUT.length];
            li.appendChild(dot);
            const text = el("span");
            text.appendChild(el("span", "ix-legend-name", item.label));
            text.appendChild(el("span", "ix-legend-sub", item.sub));
            li.appendChild(text);
            li.title = `${item.label}: ${item.sub}`;
            return li;
        }));
    }

    async function loadCategory(filters) {
        if (REF) return renderCategory(REF.category);
        try {
            const data = await apiFetch("/api/reports/movements-by-category", { date_from: filters.date_from, date_to: filters.date_to });
            const items = (data.items || []).slice(0, 6);
            if (!items.length) return showCardMessage("chart-category", "Sin datos");
            const total = items.reduce((sum, i) => sum + (Number(i.total_movements_count) || 0), 0);
            renderCategory({
                centerValue: fmtInt(total),
                centerLabel: "Movimientos",
                items: items.map((i) => ({
                    label: i.category_name, value: i.total_movements_count,
                    sub: `${total ? Math.round((i.total_movements_count / total) * 100) : 0}% (${fmtInt(i.total_movements_count)})`,
                })),
            });
        } catch (error) {
            showCardMessage("chart-category", errorMessage(error), true);
        }
    }

    // ------------------------------------------------------------------
    // Listas: movimientos recientes y bajo stock
    // ------------------------------------------------------------------
    function rowText(title, desc) {
        const text = el("span", "ix-row-text");
        text.appendChild(el("span", "ix-row-title", title));
        text.appendChild(el("span", "ix-row-desc", desc));
        return text;
    }

    function listMessage(containerId, message, isError) {
        $(containerId).replaceChildren(el("div", `ix-msg${isError ? " is-error" : ""}`, message));
    }

    function renderList(containerId, rows, buildRow) {
        if (!rows || !rows.length) return listMessage(containerId, "Sin datos");
        $(containerId).replaceChildren(...rows.map(buildRow));
    }

    function activityRow(r) {
        const row = el("div", "ix-row");
        row.title = `${r.title} — ${r.desc}`;
        row.appendChild(icon(r.icon, `ix-row-icon tone-${r.tone}`));
        row.appendChild(rowText(r.title, r.desc));
        const side = el("span", "ix-row-side");
        side.appendChild(el("span", "ix-row-time", r.time));
        side.appendChild(el("span", `ix-row-amount is-${r.direction}`, r.amount));
        row.appendChild(side);
        return row;
    }

    function liveActivity(item) {
        const delta = Number(item.new_stock) - Number(item.previous_stock);
        const direction = delta > 0 ? "up" : delta < 0 ? "down" : "neutral";
        const tone = { up: "green", down: "red", neutral: "blue" }[direction];
        return {
            icon: { up: "ti-arrow-up", down: "ti-arrow-down", neutral: "ti-adjustments" }[direction], tone,
            title: `${item.product_code} · ${item.product_name}`,
            desc: `${fmtQty(item.previous_stock)} → ${fmtQty(item.new_stock)} · ${item.reason || "Sin datos"} · ${item.user_name || "Sin datos"}`,
            time: fmtDateTime(item.created_at),
            amount: `${delta > 0 ? "+ " : delta < 0 ? "- " : ""}${fmtQty(Math.abs(delta))} uds.`, direction,
        };
    }

    async function loadActivity(filters) {
        if (REF) return renderList("table-adjustments", REF.activity, activityRow);
        try {
            const data = await apiFetch("/api/reports/inventory-adjustments", { date_from: filters.date_from, date_to: filters.date_to });
            renderList("table-adjustments", (data.items || []).slice(0, 5).map(liveActivity), activityRow);
        } catch (error) {
            listMessage("table-adjustments", errorMessage(error), true);
        }
    }

    function lowStockRow(r) {
        const row = el("div", "ix-row");
        row.title = `${r.title} — ${r.desc}`;
        row.appendChild(icon(r.icon, "ix-thumb"));
        row.appendChild(rowText(r.title, r.desc));
        row.appendChild(el("span", `ix-badge ${r.depleted ? "is-red" : "is-orange"}`, r.badge));
        return row;
    }

    function liveLowStock(item) {
        const depleted = Number(item.current_stock) <= 0;
        return {
            icon: "ti-package", title: item.name, depleted, badge: depleted ? "Agotado" : "Bajo stock",
            desc: `Stock actual: ${fmtQty(item.current_stock)} unidades · Mínimo: ${fmtQty(item.minimum_stock)}`,
        };
    }

    async function loadLowStock() {
        if (REF) return renderList("table-low-stock", REF.lowStock, lowStockRow);
        try {
            const data = await apiFetch("/api/reports/low-stock-products");
            renderList("table-low-stock", (data.items || []).slice(0, 5).map(liveLowStock), lowStockRow);
        } catch (error) {
            listMessage("table-low-stock", errorMessage(error), true);
        }
    }

    // ------------------------------------------------------------------
    // Tabla inferior: productos más vendidos / con más salidas
    // ------------------------------------------------------------------
    function cell(content, className) {
        const td = el("td", className);
        if (content instanceof Node) td.appendChild(content); else td.textContent = content;
        return td;
    }

    function renderTop(rows) {
        const tbody = $("table-top");
        if (!rows || !rows.length) {
            const tr = el("tr", "ix-empty");
            const td = cell("Sin datos");
            td.colSpan = 5;
            tr.appendChild(td);
            return tbody.replaceChildren(tr);
        }
        tbody.replaceChildren(...rows.map((r, idx) => {
            const tr = el("tr");
            const product = el("span", "ix-cell-product");
            product.appendChild(icon(r.icon, "ix-thumb"));
            product.appendChild(el("span", null, r.product));
            tr.append(cell(String(idx + 1)), cell(product), cell(r.category), cell(r.units, "is-center"), cell(r.revenue, "is-end"));
            tr.title = `${r.product} — ${r.category}`;
            return tr;
        }));
    }

    async function loadTop(filters) {
        if (REF) return renderTop(REF.top);
        try {
            const data = await apiFetch("/api/reports/top-products-by-exits", { date_from: filters.date_from, date_to: filters.date_to, limit: 5 });
            renderTop((data.items || []).map((i) => ({
                icon: "ti-package", product: i.product_name, category: i.category_name,
                units: fmtQty(i.total_quantity), revenue: fmtInt(i.total_movements),
            })));
        } catch (error) {
            const tbody = $("table-top");
            const tr = el("tr", "ix-empty");
            const td = cell(errorMessage(error), "is-error");
            td.colSpan = 5;
            tr.appendChild(td);
            tbody.replaceChildren(tr);
        }
    }

    // ------------------------------------------------------------------
    // Reportes secundarios (solo modo normal)
    // ------------------------------------------------------------------
    const BAR_OPTIONS = (indexAxis) => ({
        indexAxis, responsive: true, maintainAspectRatio: false,
        plugins: { legend: { position: "top", align: "start", labels: { boxWidth: 22, boxHeight: 3, padding: 14, color: AXIS_COLOR, font: AXIS_FONT } } },
        scales: {
            [indexAxis === "y" ? "x" : "y"]: { beginAtZero: true, ticks: { precision: 0, color: AXIS_COLOR, font: AXIS_FONT }, grid: GRID, border: { display: false } },
            [indexAxis === "y" ? "y" : "x"]: { grid: { display: false }, ticks: { color: AXIS_COLOR, font: AXIS_FONT } },
        },
    });

    async function loadStockMinimum() {
        const canvas = "chart-stock-minimum";
        try {
            const items = ((await apiFetch("/api/reports/stock-vs-minimum")).items || []).slice(0, 20);
            if (!items.length) return showCardMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "bar",
                data: {
                    labels: items.map((i) => shortLabel(i.name)),
                    datasets: [
                        { label: "Stock actual", data: items.map((i) => i.current_stock), backgroundColor: COLORS.blue },
                        { label: "Stock mínimo", data: items.map((i) => i.minimum_stock), backgroundColor: COLORS.gray },
                    ],
                },
                options: BAR_OPTIONS("y"),
            });
        } catch (error) {
            showCardMessage(canvas, errorMessage(error), true);
        }
    }

    async function loadNotesPeriod(filters) {
        const canvas = "chart-notes-period";
        try {
            const data = await apiFetch("/api/reports/delivery-notes-by-period", { date_from: filters.date_from, date_to: filters.date_to });
            const items = data.items || [];
            if (!items.length) return showCardMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "bar",
                data: {
                    labels: items.map((i) => fmtDate(i.date)),
                    datasets: [
                        { label: "Emitidas", data: items.map((i) => i.issued_count), backgroundColor: COLORS.blue, borderRadius: 4 },
                        { label: "Canceladas", data: items.map((i) => i.cancelled_count), backgroundColor: COLORS.red, borderRadius: 4 },
                    ],
                },
                options: BAR_OPTIONS("x"),
            });
        } catch (error) {
            showCardMessage(canvas, errorMessage(error), true);
        }
    }

    async function loadTopDelivered(filters) {
        const canvas = "chart-top-delivered";
        try {
            const data = await apiFetch("/api/reports/top-delivered-products", { date_from: filters.date_from, date_to: filters.date_to, limit: filters.limit });
            const items = data.items || [];
            if (!items.length) return showCardMessage(canvas, "Sin datos");
            const options = BAR_OPTIONS("x");
            options.plugins.legend = { display: false };
            options.plugins.tooltip = { callbacks: {
                title: (ctx) => items[ctx[0].dataIndex].product_name,
                label: (ctx) => { const i = items[ctx.dataIndex]; return ` ${fmtQty(i.total_quantity)} unidades · ${fmtMoney(i.total_amount)} en ${fmtInt(i.notes_count)} notas`; },
            } };
            renderChart(canvas, {
                type: "bar",
                data: { labels: items.map((i) => shortLabel(i.product_name)), datasets: [{ label: "Unidades entregadas", data: items.map((i) => i.total_quantity), backgroundColor: COLORS.green, borderRadius: 4 }] },
                options,
            });
        } catch (error) {
            showCardMessage(canvas, errorMessage(error), true);
        }
    }

    async function loadNotesUser(filters) {
        const canvas = "chart-notes-user";
        try {
            const data = await apiFetch("/api/reports/delivery-notes-by-user", { date_from: filters.date_from, date_to: filters.date_to });
            const items = data.items || [];
            if (!items.length) return showCardMessage(canvas, "Sin datos");
            renderChart(canvas, {
                type: "doughnut",
                data: {
                    labels: items.map((i) => shortLabel(i.user_name, 22)),
                    datasets: [{ data: items.map((i) => i.notes_count), backgroundColor: items.map((_, idx) => DONUT[idx % DONUT.length]), borderWidth: 2, borderColor: "#ffffff" }],
                },
                options: {
                    responsive: true, maintainAspectRatio: false, cutout: "58%",
                    plugins: {
                        legend: { position: "right", labels: { boxWidth: 10, boxHeight: 10, usePointStyle: true, padding: 16, color: "#3f4b5f", font: AXIS_FONT } },
                        tooltip: { callbacks: { label: (ctx) => { const i = items[ctx.dataIndex]; return ` ${i.user_name}: ${fmtInt(i.notes_count)} notas · ${fmtMoney(i.total_amount)}`; } } },
                    },
                },
            });
        } catch (error) {
            showCardMessage(canvas, errorMessage(error), true);
        }
    }

    function badge(text, cls) {
        return el("span", `badge ${cls}`, text);
    }

    /* Filas de tabla con textContent / nodos DOM (nunca HTML crudo). */
    function renderTableRows(tbodyId, items, columns, message) {
        const tbody = $(tbodyId);
        if (message || !items || !items.length) {
            const tr = el("tr");
            const td = cell(message || "Sin datos", `text-center py-4 ${message ? "text-danger" : "text-secondary"}`);
            td.colSpan = columns.length;
            tr.appendChild(td);
            return tbody.replaceChildren(tr);
        }
        tbody.replaceChildren(...items.map((item) => {
            const tr = el("tr");
            columns.forEach((column) => tr.appendChild(cell(column.render(item), column.className)));
            return tr;
        }));
    }

    function setCount(id, count) {
        $(id).textContent = `${fmtInt(count)} registro${count === 1 ? "" : "s"}`;
    }

    const NO_MOVEMENT_COLUMNS = [
        { render: (i) => i.code }, { render: (i) => i.name }, { render: (i) => i.category_name },
        { className: "text-end", render: (i) => fmtQty(i.current_stock) },
        { render: (i) => (i.last_movement_at ? fmtDateTime(i.last_movement_at) : badge("Nunca", "bg-secondary-lt")) },
        { className: "text-end", render: (i) => fmtInt(i.days_without_movement) },
    ];

    const EXCESS_COLUMNS = [
        { render: (i) => i.code }, { render: (i) => i.name }, { render: (i) => i.category_name },
        { className: "text-end", render: (i) => fmtQty(i.current_stock) },
        { className: "text-end", render: (i) => fmtQty(i.minimum_stock) },
        { className: "text-end fw-bold", render: (i) => fmtQty(i.excess_quantity) },
    ];

    async function loadTable(tbodyId, badgeId, columns, path, params) {
        try {
            const data = await apiFetch(path, params);
            renderTableRows(tbodyId, data.items, columns);
            setCount(badgeId, data.count || 0);
        } catch (error) {
            renderTableRows(tbodyId, [], columns, errorMessage(error));
            setCount(badgeId, 0);
        }
    }

    function loadReports(filters) {
        return [
            loadStockMinimum(),
            loadNotesUser(filters),
            loadNotesPeriod(filters),
            loadTopDelivered(filters),
            loadTable("table-no-movement", "badge-no-movement", NO_MOVEMENT_COLUMNS, "/api/reports/products-without-movement", { days: filters.days }),
            loadTable("table-excess", "badge-excess", EXCESS_COLUMNS, "/api/reports/excess-stock-products", { multiplier: filters.multiplier }),
        ];
    }

    // ------------------------------------------------------------------
    // Filtros y carga general (el menú móvil vive en ix_shell.js)
    // ------------------------------------------------------------------
    function getFilters() {
        return {
            date_from: $("f-date-from").value, date_to: $("f-date-to").value,
            days: $("f-days").value, multiplier: $("f-multiplier").value, limit: $("f-limit").value,
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
        authAlertShown = false;
        $("global-alert").className = "alert d-none";
        const applyButton = $("btn-apply");
        applyButton.disabled = true;
        try {
            const tasks = [loadKpis(), loadSales(filters), loadCategory(filters), loadActivity(filters), loadLowStock(), loadTop(filters)];
            if (!REF) tasks.push(...loadReports(filters));
            await Promise.allSettled(tasks);
            const stamp = $("last-update");
            if (stamp) {
                stamp.textContent = "Actualizado: " + new Date().toLocaleString("es-VE", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
            }
        } finally {
            applyButton.disabled = false;
        }
    }

    $("filters-form").addEventListener("submit", (event) => { event.preventDefault(); loadAll(); });

    $("btn-clear").addEventListener("click", () => {
        $("f-date-from").value = "";
        $("f-date-to").value = "";
        $("f-days").value = "30";
        $("f-multiplier").value = "3";
        $("f-limit").value = "10";
        loadAll();
    });

    document.querySelectorAll("[data-svg]").forEach((node) => node.appendChild(svgIcon(node.dataset.svg)));
    loadAll();
})();
