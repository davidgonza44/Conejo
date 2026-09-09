"""Approved sales-report fixtures. Only passed to templates in debug + ref=1."""
from app.utils.inventory_reference import TALADRO, DISCO, CEMENTO, DESTORNILLADORES, NIVEL, BROCA, CINTA, TORNILLO, TALADRO_20V

TABS = [('summary', 'Resumen'), ('products', 'Ventas por producto'), ('customers', 'Ventas por cliente'), ('categories', 'Ventas por categoría'), ('payments', 'Métodos de pago')]
PRODUCTS = [
    (TALADRO, 'TAL-750W', 'Herramientas eléctricas', 148, '59,200.00', '12.2%'),
    (DISCO, 'DIS-4-1/2', 'Herramientas manuales', 436, '31,320.00', '6.4%'),
    (CEMENTO, 'CEM-50KG', 'Materiales de construcción', 312, '27,040.00', '5.6%'),
    (DESTORNILLADORES, 'DES-6PZ', 'Herramientas manuales', 215, '18,700.00', '3.8%'),
    (NIVEL, 'NIV-24', 'Herramientas manuales', 184, '14,720.00', '3.0%'),
    (BROCA, 'BRO-1/2', 'Herramientas eléctricas', 173, '7,785.00', '1.6%'),
    (CINTA, 'CIN-5M', 'Herramientas manuales', 162, '7,290.00', '1.5%'),
    (TORNILLO, 'TOR-1-1/2', 'Ferretería básica', 520, '4,680.00', '1.0%'),
]
CUSTOMERS = [
    ('Constructora del Norte S.A.', 'J-00123456-7', 28, 148, '59,200.00', '2,114.29', 'Activo'),
    ('Ferretería San José', 'J-00234567-8', 24, 135, '31,320.00', '1,305.00', 'Activo'),
    ('Inversiones López C.A.', 'J-00345678-9', 18, 96, '27,040.00', '1,502.22', 'Activo'),
    ('Distribuidora Ramos', 'J-00456789-0', 16, 74, '18,700.00', '1,168.75', 'Activo'),
    ('Público en general', 'V-00000000-0', 42, 215, '14,720.00', '350.48', 'Activo'),
    ('Ferremax C.A.', 'J-00567890-1', 12, 68, '7,785.00', '648.75', 'Activo'),
    ('Materiales Premier', 'J-00678901-2', 10, 56, '7,290.00', '729.00', 'Inactivo'),
    ('Aceros del Centro', 'J-00789012-3', 8, 45, '4,680.00', '585.00', 'Activo'),
]
# label, value, change, Lucide icon, tone
SALES_KPI = ('Ventas del mes', '$ 486,250.00', '18.6%', 'dollar', 'blue')
TICKET_KPI = ('Ticket promedio', '$ 1,256.80', '7.3%', 'tag', 'purple')
CLIENT_KPI = ('Clientes activos', '78', '17.0%', 'users', 'blue')
REPORT = {
    'date': '01 may. 2024 - 31 may. 2024', 'compare': 'Comparar con: 01 abr. 2024 - 30 abr. 2024',
    'kpis': {
        'categories': [('Categorías activas','6','2','layers','blue'),('Ingresos por categoría','$ 486,250.00','18.6%','dollar','green'),('Categoría líder','Herr. eléctricas','9.4%','trophy','orange'),('Crecimiento prom.','+8.2%','1.6%','bars','purple')],
        'payments': [('Métodos activos','5','1','card','blue'),('Ingresos cobrados','$ 486,250.00','16.9%','cash','green'),('Método principal','Transferencia','4.1%','transfer','purple'),('Ticket prom. por método','$ 1,248.60','5.8%','card','orange')],
        'summary': [SALES_KPI, ('Órdenes de venta', '142', '6.4%', 'cart', 'green'), TICKET_KPI, CLIENT_KPI],
        'products': [('Productos vendidos', '1,247', '12.5%', 'boxes', 'blue'), ('Unidades vendidas', '5,862 uds.', '8.4%', 'cart', 'green'), ('Ingresos por producto', '$ 486,250.00', '18.6%', 'dollar', 'blue'), ('Ticket prom. por producto', '$ 390.10', '6.2%', 'tag', 'purple')],
        'customers': [CLIENT_KPI, ('Clientes recurrentes', '64%', '5.8%', 'refresh', 'green'), ('Ingresos por cliente', '$ 486,250.00', '18.6%', 'dollar', 'blue'), TICKET_KPI],
    },
    'products': PRODUCTS, 'customers': CUSTOMERS, 'featured': TALADRO_20V,
    'donuts': {
        'categories': ('Participación por categoría','6','Categorías',[('Herramientas eléctricas','40.8% ($198,450.00)',40.8),('Herramientas manuales','26.1% ($126,870.00)',26.1),('Materiales de construcción','14.9% ($72,340.00)',14.9),('Ferretería básica','9.9% ($48,260.00)',9.9),('Protección y seguridad','5.6% ($27,180.00)',5.6),('Otros','2.7% ($13,150.00)',2.7)]),
        'payments': ('Distribución por método','142','Transacciones',[('Transferencia','42.8% (52)',42.8),('Efectivo','25.4% (36)',25.4),('Tarjeta','19.7% (28)',19.7),('Pago móvil','13.4% (19)',13.4),('Crédito','4.9% (7)',4.9)]),
        'summary': ('Ventas por categoría', '$ 486,250', 'Ingresos totales', [('Herramientas eléctricas', '29% ($ 141,012)',29), ('Herramientas manuales','26% ($ 126,425)',26), ('Materiales de construcción','19% ($ 92,388)',19), ('Ferretería básica','14% ($ 68,075)',14), ('Protección y seguridad','8% ($ 38,900)',8), ('Otros','4% ($ 19,450)',4)]),
        'products': ('Participación por categoría', '1,247', 'Productos', [('Herramientas eléctricas','28% (349)',28), ('Herramientas manuales','32% (399)',32), ('Materiales de construcción','18% (224)',18), ('Ferretería básica','15% (187)',15), ('Otros','7% (88)',7)]),
        'customers': ('Distribución por tipo de cliente','78','Clientes',[('Constructoras','28% (22)',28), ('Ferreterías','24% (19)',24), ('Distribuidores','19% (15)',19), ('Público general','18% (14)',18), ('Otros','11% (8)',11)]),
    },
    'executive': [('trophy','orange','Mejor categoría:','Herramientas eléctricas'), ('chart','green','Mayor crecimiento:','Clientes activos (+17.0%)'), ('bulb','blue','Mayor ticket:','Constructora del Norte S.A.'), ('boxes','orange','Mayor producto:',TALADRO['name']), ('users','blue','Conversión estimada:','64%')],
    'activity': [('cart','green','Nueva venta','Constructora del Norte S.A.','Hoy, 11:42 a.m.','+ $ 8,920.00'), ('users','blue','Cliente recurrente','Ferretería San José','Hoy, 10:15 a.m.','5ta compra'), ('dollar','green','Pago recibido','Inversiones López C.A.','Hoy, 09:08 a.m.','+ $ 12,400.00'), ('tag','purple','Nueva venta','Público en general','Ayer, 04:35 p.m.','+ $ 2,450.00'), ('bulb','orange','Cliente recurrente','Ferremax C.A.','Ayer, 03:20 p.m.','3ra compra')],
    'months': ['Jun','Jul','Ago','Sep','Oct','Nov','Dic','Ene','Feb','Mar','Abr','May',''],
    'categories': [
        ('Herramientas eléctricas',348,'1,240','198,450.00','40.8%','22.4%','drill','teal'),
        ('Herramientas manuales',512,'2,186','126,870.00','26.1%','14.8%','hammer','orange'),
        ('Materiales de construcción',278,'892','72,340.00','14.9%','8.6%','bricks','red'),
        ('Ferretería básica',215,'1,024','48,260.00','9.9%','6.2%','bolt','muted'),
        ('Protección y seguridad',184,'620','27,180.00','5.6%','4.1%','helmet','orange'),
        ('Otros',96,'320','13,150.00','2.7%','12.3%','boxes','muted'),
    ],
    'payments': [('Transferencia',52,'208,120.00','4,002.31','42.8%','bank','muted'),('Efectivo',36,'96,580.00','2,682.78','19.9%','cash','green'),('Tarjeta',28,'88,430.00','3,158.21','18.2%','card','blue'),('Pago móvil',19,'54,720.00','2,880.00','11.3%','smartphone','blue'),('Crédito',7,'38,400.00','5,485.71','7.8%','file','muted')],
    'breakdown_summaries': {
        'categories': [('chart','green','Mayor crecimiento:','Herramientas eléctricas (+22.4%)'),('bars','blue','Mayor ticket:','Materiales de construcción ($81.12 promedio)'),('trophy','orange','Mayor participación:','Herramientas manuales (26.1%)')],
        'payments': [('trophy','orange','Mayor participación:','Transferencia (42.8%)'),('bars','blue','Mayor ticket:','Crédito ($ 5,485.71 promedio)'),('chart','green','Mayor crecimiento:','Tarjeta (+9.4%)'),('shield','blue','Método más estable:','Efectivo')],
    },
    'categories_series': [[50,55,63,69,64,75,73,80,81,91,88,95,87],[33,35,43,47,45,49,49,52,55,59,57,60,58],[22,24,27,30,31,36,35,35,38,41,41,44,44],[14,17,21,23,23,26,28,29,32,33,34,33,33],[8,10,13,15,16,18,18,19,20,21,21,20,19],[6,7,8,9,9,10,10,10,11,12,12,12,13]],
    'payments_series': [[36,46,51,58,57,65,61,69,69,74,84,79,90],[23,28,34,38,38,42,39,43,45,46,50,48,52],[17,21,27,29,28,33,31,32,34,36,39,38,41],[11,14,16,17,18,20,18,19,21,23,25,25,27],[5,7,7,7,7,8,7,7,8,9,11,10,10]],
    'summary_series': [[35,43,52,61,50,58,66,59,70,66,74,83,79,86], [18,18,25,31,26,31,38,34,40,38,45,48,42,45]],
    'series': [[28,39,54,60,49,60,53,63,63,72,87,74,82], [17,18,29,34,28,29,34,38,37,40,44,38,40], [12,11,22,26,23,35,27,29,29,31,34,29,30], [5,7,9,11,11,14,15,15,16,17,18,16,17], [0,0,1,2,2,2,2,3,3,3,4,2,3]],
}
