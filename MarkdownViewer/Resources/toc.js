(function() {
    var headings = [];
    var activeId = null;
    var scheduled = false;

    function sendActive(id) {
        if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.outlinePosition) {
            return;
        }
        window.webkit.messageHandlers.outlinePosition.postMessage({ id: id || null });
    }

    function collectHeadings() {
        headings = Array.prototype.slice.call(document.querySelectorAll("h1, h2, h3, h4, h5, h6"));
    }

    function updateActive() {
        if (headings.length === 0) {
            if (activeId !== null) {
                activeId = null;
                sendActive(null);
            }
            return;
        }

        var offset = 120;
        var current = null;

        for (var i = 0; i < headings.length; i++) {
            var rect = headings[i].getBoundingClientRect();
            if (rect.top - offset <= 0) {
                current = headings[i];
            } else {
                break;
            }
        }

        var nextId = (current && current.id) ? current.id : headings[0].id;
        if (!nextId || nextId === activeId) {
            return;
        }
        activeId = nextId;
        sendActive(activeId);
    }

    function scheduleUpdate() {
        if (scheduled) {
            return;
        }
        scheduled = true;
        requestAnimationFrame(function() {
            scheduled = false;
            updateActive();
        });
    }

    function init() {
        collectHeadings();
        updateActive();
        window.addEventListener("scroll", scheduleUpdate, { passive: true });
        window.addEventListener("resize", scheduleUpdate);
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
