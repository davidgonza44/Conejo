/* Shell "ix" compartido: menú lateral en móvil y grupos desplegables del sidebar. */
(function () {
    "use strict";

    const shell = document.getElementById("ix-shell");
    const toggle = document.getElementById("ix-menu-toggle");
    if (shell && toggle) {
        toggle.addEventListener("click", () => {
            const open = shell.classList.toggle("is-nav-open");
            toggle.setAttribute("aria-expanded", String(open));
        });
    }

    document.querySelectorAll(".ix-nav-group > button").forEach((button) => {
        button.addEventListener("click", () => {
            const group = button.parentElement;
            const list = document.getElementById(button.getAttribute("aria-controls"));
            const open = group.classList.toggle("is-open");
            button.classList.toggle("is-active", open);
            button.setAttribute("aria-expanded", String(open));
            if (list) list.hidden = !open;
            const chevron = button.querySelector(".ix-nav-chevron");
            if (chevron) chevron.className = `ti ti-chevron-${open ? "up" : "right"} ix-nav-chevron`;
        });
    });
})();
