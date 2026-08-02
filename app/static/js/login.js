/* Lógica de la página /login: login tradicional y passwordless.
   Google NO usa fetch: es una redirección normal del navegador. */

(function () {
    "use strict";

    const $ = (id) => document.getElementById(id);

    function showAlert(el, message) {
        el.textContent = message;
        el.classList.remove("d-none");
    }

    function hideAlerts(...els) {
        els.forEach((el) => el.classList.add("d-none"));
    }

    async function postJson(url, body) {
        const response = await fetch(url, {
            method: "POST",
            credentials: "same-origin",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });
        let data = {};
        try {
            data = await response.json();
        } catch (error) {
            // Respuesta sin cuerpo JSON: se deja data vacío.
        }
        return { ok: response.ok, status: response.status, data };
    }

    // ------------------------------------------------------------------
    // Login tradicional (email o username + contraseña)
    // ------------------------------------------------------------------
    $("login-form").addEventListener("submit", async (event) => {
        event.preventDefault();
        hideAlerts($("login-error"));

        const identifier = $("login-identifier").value.trim();
        const password = $("login-password").value;
        if (!identifier || !password) {
            showAlert($("login-error"), "Ingrese usuario/correo y contraseña.");
            return;
        }

        const button = $("login-submit");
        button.disabled = true;
        try {
            const { ok, data } = await postJson("/api/auth/login", { identifier, password });
            if (ok) {
                window.location.href = "/dashboard";
                return;
            }
            showAlert($("login-error"), data.error || "No fue posible iniciar sesión.");
        } catch (error) {
            showAlert($("login-error"), "Error de conexión con el servidor.");
        } finally {
            button.disabled = false;
        }
    });

    // ------------------------------------------------------------------
    // Passwordless: solicitar código
    // ------------------------------------------------------------------
    $("pwl-request").addEventListener("click", async () => {
        hideAlerts($("pwl-info"), $("pwl-error"), $("pwl-token-box"));

        const email = $("pwl-email").value.trim();
        if (!email) {
            showAlert($("pwl-error"), "Ingrese su correo electrónico.");
            return;
        }

        const button = $("pwl-request");
        button.disabled = true;
        try {
            const { ok, data } = await postJson("/api/auth/passwordless/request", { email });
            if (!ok) {
                showAlert($("pwl-error"), data.error || "No fue posible solicitar el código.");
                return;
            }
            showAlert(
                $("pwl-info"),
                "Si el correo está registrado, recibirá un código de acceso temporal."
            );
            if (data.dev_token) {
                // Solo llega en APP_ENV=development para probar sin correo configurado.
                $("pwl-dev-token").textContent = data.dev_token;
                $("pwl-token").value = data.dev_token;
                $("pwl-token-box").classList.remove("d-none");
            }
        } catch (error) {
            showAlert($("pwl-error"), "Error de conexión con el servidor.");
        } finally {
            button.disabled = false;
        }
    });

    // ------------------------------------------------------------------
    // Passwordless: verificar código
    // ------------------------------------------------------------------
    $("pwl-verify").addEventListener("click", async () => {
        hideAlerts($("pwl-info"), $("pwl-error"));

        const email = $("pwl-email").value.trim();
        const token = $("pwl-token").value.trim();
        if (!email || !token) {
            showAlert($("pwl-error"), "Ingrese el correo y el código recibido.");
            return;
        }

        const button = $("pwl-verify");
        button.disabled = true;
        try {
            const { ok, data } = await postJson("/api/auth/passwordless/verify", { email, token });
            if (ok) {
                window.location.href = "/dashboard";
                return;
            }
            showAlert($("pwl-error"), data.error || "Código inválido o vencido.");
        } catch (error) {
            showAlert($("pwl-error"), "Error de conexión con el servidor.");
        } finally {
            button.disabled = false;
        }
    });
})();
