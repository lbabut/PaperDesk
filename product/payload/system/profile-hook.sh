# RMSSH-BEGIN
# Start RMSSH only for LiTerm's local login shell, never for inbound SSH.
if [ "${TERM:-}" = "xterm-256color" ] && [ -z "${SSH_CONNECTION:-}" ] && [ -z "${RMSSH_MENU_ACTIVE:-}" ]; then
    export RMSSH_MENU_ACTIVE=1
    exec /home/root/.local/bin/rmssh-menu
fi
# RMSSH-END
