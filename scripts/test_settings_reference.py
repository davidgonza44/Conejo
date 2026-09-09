"""Disposable no-database harness for settings and integrated reference views.

Run from repository root. Blocks dotenv loading and never initializes SQLAlchemy,
OAuth, SMTP, uploads, or an application database. Synthetic login exists only here.
"""
import os
os.environ['PYTHON_DOTENV_DISABLED'] = '1'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flask import Flask, request
from flask_login import UserMixin
from app.extensions import login_manager
from app.routes.pages import pages_bp

ROOT = Path(__file__).resolve().parents[1]
app = Flask(__name__, template_folder=str(ROOT / 'app/templates'), static_folder=str(ROOT / 'app/static'))
app.secret_key = 'disposable-reference-harness-only'
app.debug = True
login_manager.init_app(app)
app.register_blueprint(pages_bp)

class PreviewUser(UserMixin):
    id = 'reference-only'
    name = 'Administrador'
    email = 'admin@example.invalid'
    role = 'admin'
    profile_photo_url = None

@login_manager.request_loader
def preview_user(req):
    if req.headers.get('X-Preview-Role') == 'anonymous':
        return None
    user = PreviewUser()
    user.role = req.headers.get('X-Preview-Role', 'admin')
    return user

@login_manager.unauthorized_handler
def unauthorized():
    return 'Authentication required', 401

if __name__ == '__main__':
    client = app.test_client()
    for tab in ('general','predictive','notifications','users','security','integrations','backup'):
        assert client.get('/settings?tab=' + tab + '&ref=1').status_code == 200
    assert client.get('/settings?tab=unknown&ref=1').status_code == 404
    assert client.get('/settings?ref=1', headers={'X-Preview-Role':'anonymous'}).status_code == 401
    for role in ('inventario','vendedor'):
        assert client.get('/settings?ref=1',headers={'X-Preview-Role':role}).status_code == 302
    for method in ('post','put','patch','delete'):
        assert getattr(client,method)('/settings?ref=1').status_code == 405
    assert b'Prophet (Meta)' not in client.get('/settings?tab=predictive').data
    assert b'notificaciones@ferreteriapro.com' in client.get('/settings?tab=notifications&ref=1').data
    assert b'notificaciones@ferreteriapro.com' not in client.get('/settings?tab=notifications').data
    fixture_markers = {'users': b'isabel.vivas@ferreteriapro.com', 'security': b'190.12.45.67', 'backup': b'/backups/ferreteria_pro'}
    for tab, marker in fixture_markers.items():
        reference = client.get('/settings?tab=' + tab + '&ref=1')
        assert marker in reference.data
        assert ('tab=' + tab + '&amp;ref=1" class="is-active"').encode() in reference.data
        normal = client.get('/settings?tab=' + tab)
        assert normal.status_code == 200
        assert marker not in normal.data
        assert b'st-unavailable' in normal.data
        for method in ('post', 'put', 'patch', 'delete'):
            assert getattr(client, method)('/settings?tab=' + tab + '&ref=1').status_code == 405
    backup = client.get('/settings?tab=backup&ref=1').get_data(as_text=True)
    for text in ('Resumen de respaldos', 'Crear respaldo ahora', 'Todo correcto', 'Restaurar respaldo seleccionado', 'Consejos y recomendaciones'):
        assert text in backup
    normal = client.get('/settings?tab=backup').get_data(as_text=True)
    assert 'no están implementados' in normal
    assert 'Todo correcto' not in normal
    app.debug = False
    assert b'Prophet (Meta)' not in client.get('/settings?tab=predictive&ref=1').data
    assert b'Ferreter\xc3\xada Pro C.A.' not in client.get('/settings?tab=general&ref=1').data
    assert b'notificaciones@ferreteriapro.com' not in client.get('/settings?tab=notifications&ref=1').data
    for tab, marker in fixture_markers.items():
        assert marker not in client.get('/settings?tab=' + tab + '&ref=1').data
    app.debug = True
    print('PASS: settings routes, active tabs, authorization, rejected mutation methods and debug-only fixture isolation; no database initialized', flush=True)
    if '--serve' in sys.argv:
        app.run(host='127.0.0.1', port=int(os.environ.get('SETTINGS_PREVIEW_PORT', '5019')), debug=True, use_reloader=False, use_debugger=False)

