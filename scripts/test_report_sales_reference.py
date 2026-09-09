"""Read-only route and fixture isolation checks; no database is initialized."""
from test_settings_reference import app

client = app.test_client()
tabs = ('summary', 'products', 'customers', 'categories', 'payments')
for tab in tabs:
    route = '/reports/sales?tab=' + tab
    response = client.get(route + '&ref=1')
    assert response.status_code == 200
    assert response.data.count(b'aria-label="Secciones del reporte"') == 1
    assert b'"pages.sales_reports"' not in response.data
    normal = client.get(route)
    assert normal.status_code == 200
    assert b'id="rs-fixture"' not in normal.data
    assert b'486,250' not in normal.data
    for method in ('post', 'put', 'patch', 'delete'):
        assert getattr(client, method)(route + '&ref=1').status_code == 405
    app.debug = False
    assert b'id="rs-fixture"' not in client.get(route + '&ref=1').data
    assert b'486,250' not in client.get(route + '&ref=1').data
    app.debug = True
    for role, status in [('anonymous',401), ('vendedor',302), ('inventario',200), ('admin',200)]:
        assert client.get(route + '&ref=1', headers={'X-Preview-Role': role}).status_code == status
    bridge = client.get('/sales/reports?tab=' + tab + '&ref=1')
    assert bridge.status_code == 302
    assert bridge.location == '/reports/sales?tab=' + tab + '&ref=1'
assert client.get('/reports/sales?tab=trends&ref=1').status_code == 404
assert client.get('/reports/sales?tab=unknown&ref=1').status_code == 404
assert client.get('/sales/reports?ref=1', headers={'X-Preview-Role':'vendedor'}).status_code == 302
assert client.get('/sales/reports?ref=1', headers={'X-Preview-Role':'anonymous'}).status_code == 401
assert b'id="ix-nav-pred"' in client.get('/dashboard?ref=1').data
assert b'id="ix-nav-pred"' in client.get('/dashboard').data
assert client.get('/reports?ref=1').status_code == 200
print('PASS: five tabs, unknown-tab rejection, role permissions, legacy redirects, debug/ref isolation, rejected mutation methods, Inicio predictive navigation; no DB initialized or writes.')
