"""Product drawer isolation using the existing no-database reference harness."""
from copy import deepcopy
from test_settings_reference import app
from app.utils.inventory_reference import PRODUCTS, MOVEMENTS


def verify_product_drawer():
    before = deepcopy((PRODUCTS, MOVEMENTS))
    client = app.test_client()
    markup = client.get('/products?ref=1').get_data(as_text=True)
    for marker in ('np-drawer', 'method="dialog"', 'np-save', 'maxlength="500"', 'np-image'):
        assert marker in markup, marker
    assert markup.count('id="np-drawer"') == 1
    for route in ('products', 'categories', 'suppliers', 'inventory', 'dashboard'):
        response = client.get(f'/{route}?ref=1')
        assert response.status_code == 200, route
        assert 'Análisis predictivo' in response.get_data(as_text=True)
        if route != 'products':
            assert b'ix_product_drawer' not in response.data
    assert b'ix_product_drawer' not in client.get('/products').data
    app.debug = False
    assert b'ix_product_drawer' not in client.get('/products?ref=1').data
    app.debug = True
    assert client.get('/products?ref=1', headers={'X-Preview-Role': 'anonymous'}).status_code == 401
    assert (PRODUCTS, MOVEMENTS) == before
    assert 'sqlalchemy' not in app.extensions
    print('PASS: product drawer markers, five reference routes, sidebar, normal/debug isolation, auth and unchanged fixtures; no database initialized')


if __name__ == '__main__':
    verify_product_drawer()
