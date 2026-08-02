/* Mi perfil: subir y eliminar foto de perfil contra /api/auth/me/profile-photo. */
(function () {
    "use strict";

    const $ = (id) => document.getElementById(id);
    const IMAGE_MAX_BYTES = 2 * 1024 * 1024;
    const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "webp"];

    class ApiError extends Error {
        constructor(status, message) {
            super(message);
            this.status = status;
        }
    }

    async function apiFetch(path, { method = "GET", body = null } = {}) {
        const options = { method, credentials: "same-origin" };
        if (body instanceof FormData) {
            options.body = body;
        } else if (body !== null) {
            options.headers = { "Content-Type": "application/json" };
            options.body = JSON.stringify(body);
        }

        let response;
        try {
            response = await fetch(path, options);
        } catch (error) {
            throw new ApiError(0, "Error de conexión con el servidor.");
        }

        let data = {};
        try {
            data = await response.json();
        } catch (error) {
            // sin cuerpo JSON
        }
        if (!response.ok) {
            throw new ApiError(response.status, data.error || `Error HTTP ${response.status}.`);
        }
        return data;
    }

    function errorMessage(error) {
        if (!(error instanceof ApiError)) return "Error inesperado.";
        switch (error.status) {
            case 401: return "Su sesión expiró. Vuelva a iniciar sesión.";
            case 403: return "No tiene permisos para realizar esta acción.";
            default: return error.message;
        }
    }

    function showAlert(kind, message) {
        const alert = $("page-alert");
        alert.className = `alert alert-${kind}`;
        alert.textContent = message;
        alert.classList.remove("d-none");
    }

    function hideAlert() {
        $("page-alert").classList.add("d-none");
    }

    function showFormError(message) {
        const box = $("profile-form-error");
        box.textContent = message;
        box.classList.remove("d-none");
    }

    function hideFormError() {
        $("profile-form-error").classList.add("d-none");
    }

    function validateFile(file) {
        const ext = (file.name.split(".").pop() || "").toLowerCase();
        if (!IMAGE_EXTENSIONS.includes(ext)) {
            return `Formato '.${ext}' no permitido. Use jpg, jpeg, png o webp.`;
        }
        if (file.size > IMAGE_MAX_BYTES) {
            return `La imagen pesa ${(file.size / (1024 * 1024)).toFixed(1)} MB (máximo 2 MB).`;
        }
        return null;
    }

    function updateAvatar(url) {
        const holder = $("profile-avatar");
        holder.replaceChildren();
        if (url) {
            const img = document.createElement("img");
            img.src = url + "?t=" + Date.now();
            img.alt = "Foto de perfil";
            img.id = "profile-avatar-img";
            holder.appendChild(img);
            $("btn-delete-photo").disabled = false;
        } else {
            const span = document.createElement("span");
            span.className = "avatar avatar-xl bg-primary-lt";
            span.id = "profile-avatar-initials";
            span.textContent = (document.querySelector(".page-title")?.textContent || "U")[0] || "U";
            // Usar iniciales del nombre visible en la página
            const nameEl = document.querySelector("h3.mb-1");
            span.textContent = nameEl ? nameEl.textContent.trim().charAt(0).toUpperCase() : "U";
            holder.appendChild(span);
            $("btn-delete-photo").disabled = true;
        }

        // Actualizar avatar del navbar si existe
        const navAvatar = document.querySelector("header .avatar.avatar-sm");
        if (navAvatar) {
            navAvatar.replaceChildren();
            if (url) {
                const navImg = document.createElement("img");
                navImg.src = url + "?t=" + Date.now();
                navImg.alt = "Foto de perfil";
                navAvatar.appendChild(navImg);
            } else {
                const navSpan = document.createElement("span");
                navSpan.className = "avatar avatar-sm bg-primary-lt";
                const nameEl = document.querySelector("h3.mb-1");
                navSpan.textContent = nameEl ? nameEl.textContent.trim().charAt(0).toUpperCase() : "U";
                navAvatar.appendChild(navSpan);
            }
        }
    }

    async function uploadPhoto() {
        hideAlert();
        hideFormError();
        const file = $("profile-photo").files[0];
        if (!file) {
            showFormError("Seleccione una imagen antes de subir.");
            return;
        }
        const error = validateFile(file);
        if (error) {
            showFormError(error);
            return;
        }

        const btn = $("btn-upload-photo");
        btn.disabled = true;
        try {
            const formData = new FormData();
            formData.append("image", file);
            const data = await apiFetch("/api/auth/me/profile-photo", {
                method: "POST",
                body: formData,
            });
            updateAvatar(data.profile_photo_url || data.user?.profile_photo_url);
            $("profile-photo").value = "";
            showAlert("success", data.message || "Foto de perfil actualizada.");
        } catch (err) {
            console.error("Error al subir foto:", err);
            showFormError(errorMessage(err));
        } finally {
            btn.disabled = false;
        }
    }

    async function deletePhoto() {
        if (!window.confirm("¿Eliminar su foto de perfil?")) return;
        hideAlert();
        hideFormError();
        const btn = $("btn-delete-photo");
        btn.disabled = true;
        try {
            const data = await apiFetch("/api/auth/me/profile-photo", { method: "DELETE" });
            updateAvatar(null);
            $("profile-photo").value = "";
            showAlert("success", data.message || "Foto de perfil eliminada.");
        } catch (err) {
            console.error("Error al eliminar foto:", err);
            showFormError(errorMessage(err));
            btn.disabled = false;
        }
    }

    $("btn-upload-photo").addEventListener("click", uploadPhoto);
    $("btn-delete-photo").addEventListener("click", deletePhoto);
})();
