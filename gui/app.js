(() => {
  const TOKEN = window.BC250_TOKEN;
  const apiHeaders = {"X-BC250-Token": TOKEN, "Content-Type": "application/json"};
  const translations = {
    es: {
      title:"Modo gráfico para usuarios menos experimentados",
      subtitle:"Descubre. Prueba. Desbloquea. Guía sencilla y bilingüe; cada acción de hardware sigue ejecutándose en el CLI original dentro de una terminal visible.",
      refresh:"Actualizar", platform:"Plataforma", setupStatus:"Preparación", liveCUs:"CUs activas", persistence:"Persistencia al arranque", cpuStatus:"CPU", cpuRearm:"Re-arm CPU",
      cpuStock:"6c/12t stock", cpuUnlocked:"8c/16t desbloqueado",
      ready:"Preparado", notReady:"Falta ejecutar setup", enabled:"Activada", disabled:"Desactivada", unknown:"No disponible", terminalMissing:"No se encontró una terminal compatible", configuredTitle:"Perfil persistente activo — modo protegido", configuredBody:"Tu perfil WGP guardado ya se restaura al arrancar. Las pruebas de diagnóstico quedan bloqueadas para no mezclar probing live con persistencia. Estado, resultados, informes y gestión de persistencia siguen disponibles.", persistenceLocked:"Persistencia activa: desactívala/elíminala antes de volver al modo diagnóstico",
      safetyTitle:"Guarda tu trabajo antes de hacer pruebas", safetyBody:"Los WGP ocultos pueden ser físicamente defectuosos. Una prueba puede congelar la GPU o el PC entero. Nunca copies el perfil WGP de otra placa.",
      recommended:"Recomendado", wizardTitle:"Asistente guiado de primera configuración", wizardBody:"El asistente CLI comprueba el estado stock, prueba cada WGP oculto, te pide revisar el escritorio real y aplica sólo los aprobados en vivo. Nunca activa persistencia por sí solo.", startWizard:"Iniciar asistente guiado", runSetup:"Ejecutar setup",
      beginnerFlow:"FLUJO PARA PRINCIPIANTES", stepByStep:"Paso a paso", stepHint:"Ejecuta estos pasos en orden si prefieres entender cada fase en lugar de usar el asistente completo.",
      doctorTitle:"Comprobar hardware", doctorBody:"Detecta tu BC-250, dependencias y el mapa WGP de fábrica real de tu placa. No desbloquea WGP ocultos.",
      baselineTitle:"Baseline stock", baselineBody:"Comprueba que la configuración de fábrica de 24 CUs es correcta antes de probar silicio oculto.",
      scanTitle:"Escaneo compute", scanBody:"Prueba cada WGP deshabilitado de 2 CUs de forma independiente y restaura stock entre candidatos.",
      visualTitle:"Comprobación visual del escritorio", visualBody:"Activa un WGP que pasó compute, mientras mueves ratón, abres menús y ventanas. Tú indicas si viste artefactos.",
      resultsTitle:"Revisar resultados", resultsBody:"Muestra qué WGP pasaron compute, validación visual o fueron descartados.",
      applyTitle:"Validación combinada", applyBody:"Activa sólo WGP que pasaron las dos pruebas, ejecuta un verifier más fuerte y pide una última comprobación visual.",
      soakTitle:"Prueba de estabilidad de 30 minutos", soakBody:"Carga compute prolongada con vigilancia de temperatura y errores del kernel. Prueba también juegos reales antes de persistir.",
      persistTitle:"Persistencia opcional al arranque", persistBody:"Sólo después de juegos y soak limpios. Guarda el routing aprobado de esta placa y lo restaura al arrancar. No modifica BIOS/firmware.",
      run:"Ejecutar", run30:"Ejecutar 30 min", installPersistence:"Instalar persistencia",
      tools:"HERRAMIENTAS", maintenance:"Estado, recuperación y mantenimiento", statusTitle:"Estado en vivo", statusBody:"Routing actual, temperatura y estado de persistencia.", reportTitle:"Crear informe", reportBody:"Genera un informe Markdown respetuoso con la privacidad para GitHub/issues.", recoverTitle:"Recuperar prueba interrumpida", recoverBody:"Úsalo tras un reinicio/cuelgue antes de continuar el escaneo.", stockTitle:"Volver a stock en vivo", stockBody:"Restaura ahora el routing de fábrica detectado al arrancar.", persistStatusTitle:"Estado de persistencia", persistStatusBody:"Muestra el perfil guardado y el estado del servicio.", persistRemoveTitle:"Eliminar persistencia", persistRemoveBody:"Desactiva la restauración al arranque y vuelve al routing stock.",
      cpuSection:"CPU UNLOCK", cpuTitle:"Desbloqueo de CPU 6c/12t → 8c/16t", cpuBody:"Función validada en la placa de referencia. El desbloqueo es volátil y requiere un reinicio en caliente para que aparezcan los 8 núcleos.", cpuStatusTitle:"Estado CPU", cpuStatusBody:"Muestra hilos presentes, resultados de pruebas y estado del re-arm.", cpuUnlockTitle:"Desbloquear 8c/16t", cpuUnlockBody:"Prepara la máscara 0x77 → 0xFF. No reinicia automáticamente; reinicia en caliente cuando quieras activar los 16 hilos.", cpuQuickTitle:"Prueba rápida", cpuQuickBody:"Prueba los cores físicos 3 y 7 y después todos los hilos.", cpuDeepTitle:"Prueba profunda", cpuDeepBody:"5 min por core oculto + 10 min todos los hilos. Necesaria antes del re-arm automático.", cpuAdvanced:"AVANZADO", cpuRearmTitle:"Re-arm automático tras arranque en frío", cpuRearmBody:"Desactivado por defecto. Ahorra ejecutar cpu unlock manualmente después de un cold boot, pero NO evita el reinicio: el equipo seguirá en 6c/12t hasta que tú hagas un warm reboot. Nunca reinicia solo.", cpuRearmToggle:"Activar re-arm automático", cpuRearmStatus:"Ver estado del re-arm",
      steamTitle:"Herramientas de actualización de SteamOS", steamBody:"El soporte SteamOS es experimental. Ejecuta Verificar después de cada actualización; Reparar sólo si Verificar detecta componentes ausentes.", verify:"Verificar", repair:"Reparar",
      transparentTitle:"Transparente por diseño", transparentBody:"El modo gráfico nunca escribe registros de GPU directamente. Los botones sólo lanzan comandos permitidos del CLI BC-250 CU Unlock Suite en una terminal visible. Si la GUI falla, el CLI sigue siendo totalmente usable.",
      closeGui:"Cerrar modo gráfico", cancel:"Cancelar", continue:"Continuar",
      confirmWriteTitle:"Esta acción modifica temporalmente el routing de la GPU", confirmWriteText:"Guarda tu trabajo. El CLI restaurará stock cuando corresponda, pero un WGP defectuoso puede congelar el sistema.",
      confirmPersistTitle:"Confirmar cambio de persistencia", confirmPersistText:"Esta acción cambia la restauración al arranque. El CLI volverá a validar el perfil y pedirá confirmación final en la terminal.",
      confirmSystemTitle:"Confirmar cambio del sistema", confirmSystemText:"Esta acción puede instalar o reparar paquetes/herramientas del sistema. Los detalles y la contraseña sudo seguirán apareciendo en la terminal.",
      confirmCpuTitle:"Confirmar acción de CPU", confirmCpuText:"Los dos cores extra pueden haber sido deshabilitados por un motivo. Guarda tu trabajo, valida temperaturas y recuerda que un cold power cycle devuelve la CPU a stock.", confirmCpuRearmTitle:"Confirmar re-arm automático de CPU", confirmCpuRearmText:"Opción avanzada y desactivada por defecto. Sólo evita repetir cpu unlock tras un cold boot; todavía tendrás que hacer un warm reboot para activar 8c/16t. La suite nunca reiniciará el equipo automáticamente.",
      terminalOpened:"Terminal abierta", commandCopied:"Comando copiado", noTerminal:"No se encontró una terminal compatible. Copia y ejecuta este comando manualmente:", launchFailed:"No se pudo abrir la terminal", completed:"Comando finalizado correctamente", failed:"El comando terminó con error; revisa la terminal", serverStopping:"Cerrando modo gráfico…", footerNotice:"Herramienta experimental de hardware: úsala con responsabilidad y mantén una vía de recuperación. Desarrollada con ayuda de OpenAI ChatGPT (GPT-5.6 Sol); las decisiones y la validación sobre el hardware siguen siendo responsabilidad del usuario."
    },
    en: {
      title:"Graphical mode for less experienced users",
      subtitle:"Discover. Test. Unlock. Simple bilingual guide; every hardware action still runs in the original CLI inside a visible terminal.",
      refresh:"Refresh", platform:"Platform", setupStatus:"Setup", liveCUs:"Live CUs", persistence:"Boot persistence", cpuStatus:"CPU", cpuRearm:"CPU re-arm",
      cpuStock:"6c/12t stock", cpuUnlocked:"8c/16t unlocked",
      ready:"Ready", notReady:"Run setup first", enabled:"Enabled", disabled:"Disabled", unknown:"Unavailable", terminalMissing:"No compatible terminal found", configuredTitle:"Persistent profile active — protected mode", configuredBody:"Your saved WGP profile is already restored at boot. Diagnostic tests are locked to avoid mixing live probing with boot persistence. Status, results, reports and persistence management remain available.", persistenceLocked:"Boot persistence is active: remove/disable it before returning to diagnostic mode",
      safetyTitle:"Save your work before testing", safetyBody:"Hidden WGPs can be physically defective. A test may freeze the GPU or the whole PC. Never copy another board's WGP profile.",
      recommended:"Recommended", wizardTitle:"First-time guided assistant", wizardBody:"The CLI wizard checks stock, tests each hidden WGP, asks you to inspect the real desktop, and applies only approved WGPs live. It never enables persistence by itself.", startWizard:"Start guided assistant", runSetup:"Run setup",
      beginnerFlow:"BEGINNER FLOW", stepByStep:"Step by step", stepHint:"Run these in order if you prefer to understand each stage instead of using the full wizard.",
      doctorTitle:"Hardware check", doctorBody:"Detects your BC-250, dependencies and the board's real factory WGP map. It does not unlock hidden WGPs.",
      baselineTitle:"Stock baseline", baselineBody:"Verifies the factory 24-CU configuration before testing any hidden silicon.",
      scanTitle:"Compute scan", scanBody:"Tests each disabled 2-CU WGP independently and restores stock between candidates.",
      visualTitle:"Visual desktop check", visualBody:"Activates one compute-PASS WGP while you move the mouse, open menus and move windows. You report whether artifacts appeared.",
      resultsTitle:"Review results", resultsBody:"Shows which WGPs passed compute, passed visual validation, or were rejected.",
      applyTitle:"Combined validation", applyBody:"Enables only WGPs that passed both gates, runs a heavier verifier and asks for one final visual check.",
      soakTitle:"30-minute stability test", soakBody:"Long combined compute load with temperature and kernel-fault monitoring. Also test real games before persistence.",
      persistTitle:"Optional boot persistence", persistBody:"Only after clean games and soak tests. Saves this board's approved routing and restores it at boot. BIOS/firmware are not modified.",
      run:"Run", run30:"Run 30 min", installPersistence:"Install persistence",
      tools:"TOOLS", maintenance:"Status, recovery and maintenance", statusTitle:"Live status", statusBody:"Current routing, temperature and persistence state.", reportTitle:"Create report", reportBody:"Generate a privacy-conscious Markdown report for GitHub/issues.", recoverTitle:"Recover interrupted test", recoverBody:"Use after a reboot/hang before continuing a scan.", stockTitle:"Return to stock live", stockBody:"Restore the factory boot-driver routing now.", persistStatusTitle:"Persistence status", persistStatusBody:"Show the saved boot profile and service state.", persistRemoveTitle:"Remove persistence", persistRemoveBody:"Disable boot restore and return to stock routing.",
      cpuSection:"CPU UNLOCK", cpuTitle:"CPU unlock 6c/12t → 8c/16t", cpuBody:"Hardware-validated on the reference board. The unlock is volatile and needs a warm reboot before all 8 cores are enumerated.", cpuStatusTitle:"CPU status", cpuStatusBody:"Show present threads, health-test results and re-arm state.", cpuUnlockTitle:"Unlock 8c/16t", cpuUnlockBody:"Arms the known 0x77 → 0xFF mask. It never reboots automatically; warm reboot when you want the 16 threads active.", cpuQuickTitle:"Quick test", cpuQuickBody:"Tests physical cores 3 and 7, then all threads.", cpuDeepTitle:"Deep test", cpuDeepBody:"5 min per hidden core + 10 min all threads. Required before automatic re-arm.", cpuAdvanced:"ADVANCED", cpuRearmTitle:"Automatic re-arm after a cold boot", cpuRearmBody:"Off by default. It saves you from manually running cpu unlock after a cold boot, but does NOT remove the reboot requirement: the current session stays at 6c/12t until you choose a warm reboot. It never reboots automatically.", cpuRearmToggle:"Enable automatic re-arm", cpuRearmStatus:"View re-arm status",
      steamTitle:"SteamOS update tools", steamBody:"SteamOS support is experimental. Run Verify after every OS update; use Repair only if Verify reports missing components.", verify:"Verify", repair:"Repair",
      transparentTitle:"Transparent by design", transparentBody:"Graphical mode never writes GPU registers directly. Buttons only launch whitelisted BC-250 CU Unlock Suite CLI commands in a visible terminal. If the GUI disappears, the CLI remains fully usable.",
      closeGui:"Stop graphical mode", cancel:"Cancel", continue:"Continue",
      confirmWriteTitle:"This action temporarily changes GPU routing", confirmWriteText:"Save your work. The CLI restores stock when appropriate, but a defective WGP can freeze the system.",
      confirmPersistTitle:"Confirm persistence change", confirmPersistText:"This action changes boot restore. The CLI will validate the profile again and request final confirmation in the terminal.",
      confirmSystemTitle:"Confirm system change", confirmSystemText:"This action may install or repair system packages/tools. Details and the sudo password prompt remain visible in the terminal.",
      confirmCpuTitle:"Confirm CPU action", confirmCpuText:"The two extra cores may have been disabled for a reason. Save your work, watch temperatures, and remember a cold power cycle returns CPU enumeration to stock.", confirmCpuRearmTitle:"Confirm automatic CPU re-arm", confirmCpuRearmText:"Advanced and off by default. This only avoids repeating cpu unlock after a cold boot; you still need a warm reboot to activate 8c/16t. The suite will never reboot the machine automatically.",
      terminalOpened:"Terminal opened", commandCopied:"Command copied", noTerminal:"No compatible terminal was found. Copy and run this command manually:", launchFailed:"Could not open the terminal", completed:"Command finished successfully", failed:"Command finished with an error; review the terminal", serverStopping:"Stopping graphical mode…", footerNotice:"Experimental hardware tool — use responsibly and keep a recovery path. Developed with assistance from OpenAI ChatGPT (GPT-5.6 Sol); hardware decisions and validation remain the user’s responsibility."
    }
  };

  let lang = localStorage.getItem("bc250-lang") || (navigator.language?.toLowerCase().startsWith("es") ? "es" : "en");
  let actions = {};
  let pendingAction = null;
  const persistenceLockedActions = new Set(["setup","wizard","doctor","baseline","scan","visual","apply","soak30","recover","stock","persist_install"]);
  const dialog = document.getElementById("confirm-dialog");
  const toast = document.getElementById("toast");

  const tr = key => translations[lang][key] || translations.en[key] || key;
  function applyLanguage() {
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-i18n]").forEach(el => el.textContent = tr(el.dataset.i18n));
    document.getElementById("lang-es").classList.toggle("active", lang === "es");
    document.getElementById("lang-en").classList.toggle("active", lang === "en");
  }
  function showToast(message, error=false, timeout=4200) {
    toast.textContent = message;
    toast.classList.toggle("error", error);
    toast.classList.add("show");
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => toast.classList.remove("show"), timeout);
  }
  async function api(path, options={}) {
    const sep = path.includes("?") ? "&" : "?";
    const url = `${path}${sep}token=${encodeURIComponent(TOKEN)}`;
    const res = await fetch(url, {...options, headers: {...apiHeaders, ...(options.headers||{})}});
    const body = await res.json();
    if (!res.ok) throw new Error(body.detail || body.error || `HTTP ${res.status}`);
    return body;
  }
  async function refreshInfo() {
    try {
      const info = await api("/api/info");
      document.getElementById("platform-value").textContent = info.platform;
      document.getElementById("setup-value").textContent = info.setupReady ? tr("ready") : tr("notReady");
      document.getElementById("setup-value").className = info.setupReady ? "good" : "warn";
      document.getElementById("cus-value").textContent = info.liveCUs == null ? "—" : `${info.liveCUs}/40`;
      document.getElementById("persist-value").textContent = info.serviceEnabled ? tr("enabled") : tr("disabled");
      document.getElementById("persist-value").className = info.serviceEnabled ? "good" : "";
      const cpuThreads = info.cpuThreads;
      document.getElementById("cpu-value").textContent = cpuThreads == null ? "—" : (cpuThreads >= 16 ? tr("cpuUnlocked") : tr("cpuStock"));
      document.getElementById("cpu-value").className = cpuThreads >= 16 ? "good" : "";
      document.getElementById("cpu-rearm-value").textContent = info.cpuRearmEnabled ? tr("enabled") : tr("disabled");
      document.getElementById("cpu-rearm-value").className = info.cpuRearmEnabled ? "good" : "";
      const cpuRearmToggle = document.getElementById("cpu-rearm-toggle");
      if (cpuRearmToggle) {
        cpuRearmToggle.checked = !!info.cpuRearmEnabled;
        cpuRearmToggle.disabled = !info.setupReady;
        cpuRearmToggle.title = info.setupReady ? "" : tr("notReady");
      }
      document.getElementById("version").textContent = `BC-250 CU Unlock Suite ${info.version}`;
      const persistentNotice = document.getElementById("persistent-mode-notice");
      persistentNotice.hidden = !info.serviceEnabled;
      document.querySelector(".hero-card")?.classList.toggle("persistence-locked", !!info.serviceEnabled);
      document.getElementById("steps")?.classList.toggle("persistence-locked", !!info.serviceEnabled);
      document.querySelectorAll(".action").forEach(btn => {
        const action = btn.dataset.action;
        let disabled = false;
        let reason = "";
        if (action !== "setup" && !info.setupReady) { disabled = true; reason = tr("notReady"); }
        if (info.serviceEnabled && persistenceLockedActions.has(action)) { disabled = true; reason = tr("persistenceLocked"); }
        btn.disabled = disabled;
        btn.title = reason;
      });
      if (!info.terminal) showToast(tr("terminalMissing"), true, 7000);
      const isSteam = /SteamOS/i.test(info.platform);
      document.getElementById("steamos-section").style.display = isSteam ? "block" : "none";
    } catch (e) { showToast(String(e), true); }
  }
  async function loadActions() {
    try { actions = await api("/api/actions"); } catch (e) { showToast(String(e), true); }
  }
  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); showToast(tr("commandCopied")); }
    catch { window.prompt(tr("noTerminal"), text); }
  }
  function requestAction(id) {
    const action = actions[id];
    if (!action) return;
    if (["write","persist","system","cpu","cpu_rearm"].includes(action.risk)) {
      pendingAction = id;
      document.getElementById("confirm-title").textContent = action.risk === "persist" ? tr("confirmPersistTitle") : action.risk === "system" ? tr("confirmSystemTitle") : action.risk === "cpu" ? tr("confirmCpuTitle") : action.risk === "cpu_rearm" ? tr("confirmCpuRearmTitle") : tr("confirmWriteTitle");
      document.getElementById("confirm-text").textContent = action.risk === "persist" ? tr("confirmPersistText") : action.risk === "system" ? tr("confirmSystemText") : action.risk === "cpu" ? tr("confirmCpuText") : action.risk === "cpu_rearm" ? tr("confirmCpuRearmText") : tr("confirmWriteText");
      document.getElementById("confirm-command").textContent = action.command;
      dialog.showModal();
    } else launchAction(id);
  }
  async function launchAction(id) {
    pendingAction = null;
    try {
      const result = await api("/api/launch", {method:"POST", body:JSON.stringify({action:id})});
      if (!result.ok) {
        if (result.error === "no_terminal") { showToast(`${tr("noTerminal")} ${result.command}`, true, 9000); await copyText(result.command); }
        else if (result.error === "persistence_active") showToast(tr("persistenceLocked"), true, 7500);
        else showToast(`${tr("launchFailed")}: ${result.detail || result.error}`, true, 7000);
        return;
      }
      showToast(`${tr("terminalOpened")}: ${result.command}`);
      pollJob(result.job);
    } catch (e) { showToast(`${tr("launchFailed")}: ${e}`, true); }
  }
  async function pollJob(job) {
    for (let i=0; i<1440; i++) {
      await new Promise(r => setTimeout(r, 2500));
      try {
        const state = await api(`/api/job?id=${encodeURIComponent(job)}`);
        if (state.done) {
          showToast(state.rc === 0 ? tr("completed") : tr("failed"), state.rc !== 0, 6500);
          refreshInfo();
          return;
        }
      } catch { return; }
    }
  }

  document.querySelectorAll(".action").forEach(btn => btn.addEventListener("click", () => requestAction(btn.dataset.action)));
  document.getElementById("cpu-rearm-toggle")?.addEventListener("change", (event) => {
    const wanted = event.target.checked;
    event.target.checked = !wanted; // update only after the visible CLI command succeeds
    requestAction(wanted ? "cpu_rearm_enable" : "cpu_rearm_disable");
  });
  document.getElementById("lang-es").addEventListener("click", () => { lang="es"; localStorage.setItem("bc250-lang",lang); applyLanguage(); refreshInfo(); });
  document.getElementById("lang-en").addEventListener("click", () => { lang="en"; localStorage.setItem("bc250-lang",lang); applyLanguage(); refreshInfo(); });
  document.getElementById("refresh").addEventListener("click", refreshInfo);
  dialog.addEventListener("close", () => { if (dialog.returnValue === "confirm" && pendingAction) launchAction(pendingAction); else pendingAction=null; });
  document.getElementById("stop").addEventListener("click", async () => { showToast(tr("serverStopping")); try { await api("/api/stop", {method:"POST", body:"{}"}); } catch {} setTimeout(() => window.close(), 500); });

  applyLanguage();
  loadActions().then(refreshInfo);
  setInterval(refreshInfo, 15000);
})();
