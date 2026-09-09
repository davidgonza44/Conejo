"""Reference layers only: reuse the existing synthetic-user, no-database harness."""
from copy import deepcopy
import re

from test_settings_reference import app
from app.utils.inventory_reference import MOVEMENTS


def verify_reference_layers():
    original = deepcopy(MOVEMENTS)
    client = app.test_client()
    response = client.get('/inventory?ref=1')
    assert response.status_code == 200
    markup = response.get_data(as_text=True)
    for marker in ('mv-drawer', 'mv-export', 'mv-filters-template', 'mv-activities-template', 'mv-detail-ENT-0098'):
        assert marker in markup, marker
    def detail(reference, html=markup):
        return re.search(r'<template id="mv-detail-' + reference + r'">(.*?)</template>', html, re.S).group(1)
    pending = detail('AJU-0025')
    completed = detail('ENT-0098')
    assert 'data-mv-edit' in pending and 'data-mv-correction' not in pending
    assert 'aún no ha sido aplicado' in pending
    assert 'Ajuste de inventario por conteo físico' in pending
    assert 'data-mv-edit' not in completed and 'data-mv-correction' in completed
    assert 'ya fue aplicado' in completed
    table = re.search(r'<tbody>(.*?)</tbody>', markup, re.S).group(1)
    assert table.count('aria-label="Ver detalle"') == 8
    assert 'Editar movimiento' not in table
    # Render canceled semantics using a private copy, without adding a fixture.
    canceled = deepcopy(MOVEMENTS)
    canceled['history']['rows'][0]['status'] = ('Cancelado', 'gray')
    with app.test_request_context('/inventory?ref=1'):
        html = app.jinja_env.get_template('inventory/_movement_layers.html').render(fixture=canceled)
    assert 'data-mv-edit' not in detail('ENT-0098', html)
    assert 'data-mv-correction' not in detail('ENT-0098', html)
    for method in ('post', 'put', 'patch', 'delete'):
        assert getattr(client, method)('/inventory?ref=1').status_code == 405
    assert client.get('/inventory?ref=1', headers={'X-Preview-Role': 'anonymous'}).status_code == 401
    assert client.get('/inventory?ref=1', headers={'X-Preview-Role': 'vendedor'}).status_code == 302
    assert client.get('/inventory?ref=1', headers={'X-Preview-Role': 'inventario'}).status_code == 200
    assert 'ix_movement_layers' not in client.get('/inventory').get_data(as_text=True)
    app.debug = False
    assert 'ix_movement_layers' not in client.get('/inventory?ref=1').get_data(as_text=True)
    app.debug = True
    assert MOVEMENTS == original
    assert len(MOVEMENTS['history']['rows']) == 8
    first = MOVEMENTS['history']['rows'][0]
    assert (first['ref'], first['qty'], first['before'], first['after']) == ('ENT-0098', '10', '138', '148')
    assert 'sqlalchemy' not in app.extensions
    print('PASS: debug/ref isolation, authentication, role checks, rejected mutation methods, fixture integrity; no database initialized')


if __name__ == '__main__':
    verify_reference_layers()
