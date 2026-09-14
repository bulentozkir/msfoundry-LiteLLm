(() => {
	const conversation = document.getElementById("conversation");
	if (conversation) conversation.scrollTop = conversation.scrollHeight;

	const form = document.querySelector("[data-chat-form]");
	if (!form) return;

	const message = form.querySelector("textarea");
	const sendButton = form.querySelector("[data-send-button]");
	const status = form.querySelector("[data-send-status]");
	const clearButton = document.querySelector("[data-clear-form] button");
	const clearWasDisabled = clearButton?.disabled;
	let submitting = false;

	form.addEventListener("submit", event => {
		if (submitting) {
			event.preventDefault();
			return;
		}
		if (!message.value.trim()) {
			event.preventDefault();
			message.setCustomValidity("Enter a message to send.");
			message.reportValidity();
			return;
		}
		submitting = true;
		sendButton.disabled = true;
		if (clearButton) clearButton.disabled = true;
		form.setAttribute("aria-busy", "true");
		status.textContent = "Waiting for a reply… This may take up to 25 seconds.";
	});

	message.addEventListener("input", () => message.setCustomValidity(""));
	message.addEventListener("keydown", event => {
		if (event.key === "Enter" && (event.ctrlKey || event.metaKey) && !event.isComposing) {
			event.preventDefault();
			form.requestSubmit();
		}
	});

	// Browsers may restore disabled controls from their back/forward cache.
	window.addEventListener("pageshow", () => {
		submitting = false;
		sendButton.disabled = false;
		if (clearButton) clearButton.disabled = clearWasDisabled;
		form.removeAttribute("aria-busy");
		status.textContent = "";
	});
})();
