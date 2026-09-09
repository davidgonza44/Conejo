/* Módulo Análisis predictivo: dibujo de gráficos a partir de los data-* del
   marcado (donuts, sparklines, evolución por categoría, precisión y medidor).
   Sin lógica de negocio: solo representa los valores ya renderizados. */
(function () {
    "use strict";

    const TONES = {
        red: "#ef4444",
        orange: "#f59e0b",
        yellow: "#facc15",
        green: "#22c55e",
        blue: "#1570ef",
        purple: "#a855f7",
        gray: "#9ca3af",
    };

    /* Ruido determinista (LCG) para que las series de referencia sean estables entre capturas. */
    function seeded(seed) {
        let s = (seed * 9301 + 49297) % 233280;
        return () => {
            s = (s * 9301 + 49297) % 233280;
            return s / 233280;
        };
    }

    function parseJSON(el, attr, fallback) {
        const raw = el.getAttribute(attr);
        if (!raw) return fallback;
        return JSON.parse(raw);
    }

    /* ---- Donuts (distribución de riesgo / prioridad / criticidad) ---- */
    document.querySelectorAll(".px-donut").forEach((box) => {
        const canvas = box.querySelector("canvas");
        if (!canvas || typeof Chart === "undefined") return;
        const values = parseJSON(box, "data-donut", []);
        const tones = parseJSON(box, "data-tones", []);
        new Chart(canvas, {
            type: "doughnut",
            data: {
                datasets: [{
                    data: values,
                    backgroundColor: tones.map((t) => TONES[t] || TONES.gray),
                    borderWidth: 2,
                    borderColor: "#fff",
                    hoverOffset: 0,
                }],
            },
            options: {
                cutout: "66%",
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                plugins: { legend: { display: false }, tooltip: { enabled: false } },
                events: [],
            },
        });
    });

    /* ---- Sparklines (columna Tendencia últimos 30 días) ---- */
    function sparkPoints(direction, seed, width, height) {
        const rnd = seeded(seed);
        const n = 18;
        const pts = [];
        for (let i = 0; i < n; i++) {
            const t = i / (n - 1);
            let base;
            if (direction === "up") base = 0.82 - t * 0.66;
            else if (direction === "down") base = 0.18 + t * 0.66;
            else base = 0.5;
            const amp = direction === "flat" ? 0.34 : 0.4;
            const y = Math.min(0.97, Math.max(0.03, base + (rnd() - 0.5) * amp));
            pts.push([2 + t * (width - 4), 2 + y * (height - 4)]);
        }
        return pts;
    }

    document.querySelectorAll(".px-spark").forEach((svg, index) => {
        const direction = svg.getAttribute("data-spark") || "flat";
        const color = svg.getAttribute("data-color") || TONES.blue;
        const width = 94;
        const height = 22;
        svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
        const pts = sparkPoints(direction, index + 7, width, height);
        const line = document.createElementNS("http://www.w3.org/2000/svg", "polyline");
        line.setAttribute("points", pts.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(" "));
        line.setAttribute("fill", "none");
        line.setAttribute("stroke", color);
        line.setAttribute("stroke-width", "1.6");
        line.setAttribute("stroke-linejoin", "round");
        line.setAttribute("stroke-linecap", "round");
        svg.appendChild(line);
    });

    /* ---- Evolución de ventas por categoría (Tendencias) ---- */
    function seriesData(from, to, seed, count) {
        const rnd = seeded(seed);
        const out = [];
        for (let i = 0; i < count; i++) {
            const t = i / (count - 1);
            const noise = (rnd() - 0.5) * Math.max(40, Math.abs(to - from) * 0.12 + 30);
            out.push(Math.max(0, Math.round(from + (to - from) * t + noise)));
        }
        return out;
    }

    document.querySelectorAll("[data-category-chart]").forEach((box) => {
        const canvas = box.querySelector("canvas");
        if (!canvas || typeof Chart === "undefined") return;
        const cfg = parseJSON(box, "data-category-chart", null);
        if (!cfg) return;
        const count = 30;
        const labels = [];
        for (let i = 0; i < count; i++) {
            const tick = Math.round((i / (count - 1)) * (cfg.labels.length - 1));
            const exact = Math.round((tick / (cfg.labels.length - 1)) * (count - 1)) === i;
            labels.push(exact ? cfg.labels[tick] : "");
        }
        new Chart(canvas, {
            type: "line",
            data: {
                labels,
                datasets: cfg.series.map((s, i) => ({
                    data: seriesData(s.from, s.to, 11 + i * 3, count),
                    borderColor: TONES[s.tone] || TONES.blue,
                    borderWidth: 1.8,
                    pointRadius: 0,
                    tension: 0.25,
                    fill: false,
                })),
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                events: [],
                layout: { padding: { top: 4, right: 6 } },
                plugins: { legend: { display: false }, tooltip: { enabled: false } },
                scales: {
                    x: {
                        grid: { display: false },
                        border: { color: "#e5e7eb" },
                        ticks: {
                            autoSkip: false, maxRotation: 0, font: { size: 9 }, color: "#6b7280",
                            callback: (v, i) => labels[i] || null, padding: 4,
                        },
                    },
                    y: {
                        min: 0, max: cfg.y_max,
                        grid: { color: "#f1f3f6" },
                        border: { display: false, dash: [3, 3] },
                        ticks: {
                            stepSize: cfg.y_step, font: { size: 9 }, color: "#6b7280", padding: 6,
                            callback: (v) => v.toLocaleString("en-US"),
                        },
                    },
                },
            },
        });
    });

    /* ---- Predicción vs. Real (Precisión del modelo) ---- */
    document.querySelectorAll("[data-accuracy-chart]").forEach((box) => {
        const canvas = box.querySelector("canvas");
        if (!canvas || typeof Chart === "undefined") return;
        const cfg = parseJSON(box, "data-accuracy-chart", null);
        if (!cfg) return;
        new Chart(canvas, {
            type: "line",
            data: {
                labels: cfg.labels,
                datasets: [
                    {
                        data: cfg.real, borderColor: "#1d5fd6", backgroundColor: "#1d5fd6",
                        borderWidth: 1.8, pointRadius: 2.4, pointHoverRadius: 2.4, tension: 0,
                    },
                    {
                        data: cfg.pred, borderColor: "#22c55e", backgroundColor: "#22c55e",
                        borderWidth: 1.8, borderDash: [5, 4], pointRadius: 2.4, pointHoverRadius: 2.4, tension: 0,
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                events: [],
                layout: { padding: { top: 6, right: 10 } },
                plugins: { legend: { display: false }, tooltip: { enabled: false } },
                scales: {
                    x: {
                        grid: { display: false },
                        border: { color: "#e5e7eb" },
                        ticks: { autoSkip: false, maxRotation: 0, font: { size: 10 }, color: "#4b5563", padding: 6 },
                    },
                    y: {
                        min: 0, max: cfg.y_max,
                        grid: { color: "#eef0f4" },
                        border: { display: false },
                        ticks: { stepSize: cfg.y_step, font: { size: 10 }, color: "#4b5563", padding: 8 },
                    },
                },
            },
        });
    });

    /* ---- Medidor semicircular (Desempeño del modelo) ---- */
    document.querySelectorAll("[data-gauge]").forEach((box) => {
        const canvas = box.querySelector("canvas");
        if (!canvas || typeof Chart === "undefined") return;
        const value = Number(box.getAttribute("data-gauge")) || 0;
        new Chart(canvas, {
            type: "doughnut",
            data: {
                datasets: [{
                    data: [value, Math.max(0, 100 - value)],
                    backgroundColor: ["#16a34a", "#e5e7eb"],
                    borderWidth: 0,
                    borderRadius: 6,
                }],
            },
            options: {
                rotation: -90,
                circumference: 180,
                cutout: "74%",
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                events: [],
                plugins: { legend: { display: false }, tooltip: { enabled: false } },
            },
        });
    });
})();
