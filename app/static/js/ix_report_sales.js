/* Read-only reference charts and local preview interactions. No API requests. */
(() => {
    'use strict';
    const source = document.getElementById('rs-fixture');
    const fixture = source ? JSON.parse(source.textContent) : null;
    const colors = ['#0866f5', '#25b65a', '#ffbb22', '#9561ef', '#45a9ef', '#aeb6c5'];
    const chartBox = document.querySelector('[data-rs-chart]');
    const tab = chartBox?.dataset.rsChart;
    function lineChart(box) {
        const summary = tab === 'summary';
        const categories = tab === 'categories';
        const payments = tab === 'payments';
        const breakdown = categories || payments;
        const names = categories ? ['Herr. eléctricas','Herr. manuales','Mat. construcción','Ferretería básica','Prot. y seguridad','Otros'] : payments ? fixture.payments.map(row => row[0]) : summary ? ['Ventas actuales', 'Período anterior'] : fixture[tab].slice(0, 5).map(row => tab === 'products' ? row[0].name : row[0]);
        const lineColors = payments ? [...colors.slice(0,4), colors[5]] : categories ? [...colors.slice(0,4),'#08b1c8',colors[5]] : colors;
        const series = breakdown ? fixture[`${tab}_series`] : summary ? fixture.summary_series : fixture.series;
        const labels = summary ? ['', ...fixture.months.slice(0,12), ''] : fixture.months;
        new Chart(box.querySelector('canvas'), {
            type: 'line',
            data: {labels, datasets: series.map((values, index) => ({
                label: names[index], data: values.map(value => value * (payments ? 1 : 1000)),
                borderColor: summary && index === 1 ? '#81b9f4' : lineColors[index],
                backgroundColor: summary ? (index === 0 ? '#0866f512' : '#81b9f4') : lineColors[index],
                borderWidth: summary ? 2 : 1.6, pointRadius: summary ? 3 : 2.8,
                pointBackgroundColor: summary && index === 1 ? '#81b9f4' : lineColors[index],
                borderDash: summary && index === 1 ? [6, 5] : [], fill: summary && index === 0, tension: 0,
            }))},
            options: {
                responsive: true, maintainAspectRatio: false, animation: false,
                plugins: {legend: {position: 'top', align: summary ? 'start' : 'center', labels: {color: '#596a88', boxWidth: payments ? 24 : 18, boxHeight: breakdown ? 0 : 2, padding: payments ? 26 : summary ? 14 : 10, font: {family: 'Arial', size: summary ? 12 : breakdown ? 11 : 9}}}, tooltip: {enabled: true}},
                scales: {
                    y: {min: 0, max: payments ? 100 : 100000, ticks: {autoSkip:false, stepSize:payments ? 20 : 20000, color:'#657594', font:{family:'Arial',size:summary?12:10}, callback:v => payments ? v : v ? `${v / 1000}K` : '0'}, grid:{color:'#edf0f6'}, border:{color:'#e4e8f0'}},
                    x: {ticks:{autoSkip:false,maxRotation:0,color:'#657594',padding:payments?6:10,font:{family:'Arial',size:summary?12:10}}, grid:{color:'#f0f2f6'}, border:{color:'#e4e8f0'}},
                },
            },
        });
    }
    function categoryBars(box) {
        const labels = [['Herramientas','eléctricas'],['Herramientas','manuales'],['Materiales de','construcción'],['Ferretería','básica'],['Protección y','seguridad'],['Otros']];
        new Chart(box.querySelector('canvas'), {
            type:'bar',
            data:{labels,datasets:[{data:fixture.categories.map(row=>Number(row[3].replaceAll(',',''))),backgroundColor:context=>{
                const gradient=context.chart.ctx.createLinearGradient(0,20,0,200);
                gradient.addColorStop(0,'#4196ff');gradient.addColorStop(1,'#0866f5');return gradient;
            },borderRadius:3,barPercentage:.75,categoryPercentage:.9}]},
            plugins:[{id:'categoryAmounts',afterDatasetsDraw(chart){
                const ctx=chart.ctx;ctx.save();ctx.fillStyle='#101832';ctx.font='bold 11px Arial';ctx.textAlign='center';
                chart.getDatasetMeta(0).data.forEach((bar,i)=>ctx.fillText('$'+Number(fixture.categories[i][3].replaceAll(',','')).toLocaleString('en-US'),bar.x,bar.y-8));ctx.restore();
            }}],
            options:{responsive:true,maintainAspectRatio:false,animation:false,plugins:{legend:{display:false}},scales:{
                y:{min:0,max:250000,ticks:{stepSize:50000,color:'#657594',font:{size:10},callback:v=>v?`${v/1000}K`:'0'},grid:{color:'#edf0f6'},border:{display:false}},
                x:{ticks:{autoSkip:false,maxRotation:0,color:'#657594',font:{family:'Arial',size:10}},grid:{display:false},border:{color:'#e4e8f0'}}
            }}
        });
    }
    if (fixture && typeof Chart !== 'undefined') {
        if (chartBox) lineChart(chartBox);
        const bars = document.querySelector('[data-rs-bars]');
        if (bars) categoryBars(bars);
        document.querySelectorAll('[data-rs-donut]').forEach(box => {
            const values = JSON.parse(box.dataset.rsDonut);
            const tones = values.length === 6 ? [...colors.slice(0,4), '#08b1c8', colors[5]] : [...colors.slice(0,4), colors[5]];
            new Chart(box.querySelector('canvas'), {type:'doughnut',data:{datasets:[{data:values,backgroundColor:tones,borderWidth:1,borderColor:'#fff'}]},options:{responsive:true,maintainAspectRatio:false,animation:false,cutout:box.dataset.summary === '1' ? '66%' : '64%',plugins:{legend:{display:false},tooltip:{enabled:false}}}});
        });
    }
    const dialog = document.getElementById('rs-dialog');
    function preview(message) {
        dialog.querySelector('p').textContent = message;
        dialog.showModal();
    }
    document.querySelectorAll('[data-rs-preview]').forEach(button => button.addEventListener('click', () => preview('Vista de referencia: este control no modifica datos ni consulta registros reales.')));
    document.querySelectorAll('[data-rs-detail]').forEach(button => button.addEventListener('click', () => {
        const row = fixture[tab][Number(button.dataset.rsDetail)];
        const amount = tab === 'categories' ? row[3] : tab === 'payments' ? row[2] : row[4];
        const name = tab === 'products' ? row[0].name : row[0];
        preview(`Datos de ejemplo: ${name}. Ingresos: $ ${amount}. No corresponde a un registro real.`);
    }));
    document.querySelector('[data-rs-export="pdf"]')?.addEventListener('click', () => window.print());
    document.querySelector('[data-rs-export="csv"]')?.addEventListener('click', () => {
        if (!fixture) return;
        const rows = tab === 'categories' ? [['Categoría','Productos vendidos','Unidades','Ingresos','Participación','Variación'], ...fixture.categories.map(row => row.slice(0,6))] : tab === 'payments' ? [['Método','Transacciones','Monto total','Ticket promedio','Participación'], ...fixture.payments.map(row => row.slice(0,5))] : tab === 'products' ? [['Producto','Código','Categoría','Unidades','Ingresos','Participación'], ...fixture.products.map(row => [row[0].name,...row.slice(1)])] : tab === 'customers' ? [['Cliente','RIF','Compras','Productos','Total','Ticket promedio','Estado'],...fixture.customers] : [['Indicador','Valor','Variación'],...fixture.kpis.summary.map(row => row.slice(0,3))];
        const csv = [['VISTA DE REFERENCIA — DATOS DE EJEMPLO'],...rows].map(row => row.map(value => `"${String(value).replaceAll('"','""')}"`).join(',')).join('\r\n');
        const url = URL.createObjectURL(new Blob(['\ufeff',csv],{type:'text/csv;charset=utf-8'}));
        const link = document.createElement('a'); link.href = url; link.download = `referencia-ventas-${tab}.csv`; link.click(); URL.revokeObjectURL(url);
    });
})();

