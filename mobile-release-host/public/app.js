const loginCard = document.querySelector("#login-card");
const releaseCard = document.querySelector("#release-card");
const emptyCard = document.querySelector("#empty-card");
const loginForm = document.querySelector("#login-form");
const loginMessage = document.querySelector("#login-message");
const installLink = document.querySelector("#install-link");

function setMessage(element, value) {
  element.textContent = value;
}

async function loadRelease() {
  const response = await fetch("/api/release", { credentials: "same-origin", cache: "no-store" });
  if (response.status === 404) {
    const body = await response.json();
    setMessage(document.querySelector("#empty-message"), body.error || "No approved build is available yet.");
    loginCard.classList.add("hidden");
    emptyCard.classList.remove("hidden");
    return;
  }
  if (!response.ok) throw new Error("Your sign-in has expired. Enter the access code again.");
  const release = await response.json();
  const manifest = new URL(release.manifest_url);
  if (manifest.protocol !== "https:" || manifest.origin !== window.location.origin) {
    throw new Error("The install link failed its HTTPS host check.");
  }
  document.querySelector("#version").textContent = release.marketing_version;
  document.querySelector("#build-number").textContent = release.build_number;
  document.querySelector("#build-badge").textContent = `Build ${release.build_number}`;
  document.querySelector("#release-notes").textContent = release.release_notes || "Maintenance and stability updates.";
  installLink.href = `itms-services://?action=download-manifest&url=${encodeURIComponent(manifest.toString())}`;
  installLink.classList.remove("hidden");
  loginCard.classList.add("hidden");
  emptyCard.classList.add("hidden");
  releaseCard.classList.remove("hidden");
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const passwordInput = document.querySelector("#access-code");
  const button = loginForm.querySelector("button");
  button.disabled = true;
  setMessage(loginMessage, "Checking access…");
  try {
    const response = await fetch("/api/session", {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password: passwordInput.value }),
    });
    const body = await response.json();
    passwordInput.value = "";
    if (!response.ok) throw new Error(body.error || "Access was not accepted.");
    await loadRelease();
  } catch (error) {
    setMessage(loginMessage, error.message || "Unable to connect. Try again.");
  } finally {
    button.disabled = false;
  }
});

document.querySelector("#sign-out").addEventListener("click", async () => {
  await fetch("/api/logout", { method: "POST", credentials: "same-origin", cache: "no-store" });
  releaseCard.classList.add("hidden");
  installLink.removeAttribute("href");
  installLink.classList.add("hidden");
  loginCard.classList.remove("hidden");
  setMessage(loginMessage, "Signed out.");
});
