import { useState, type FormEvent } from "react";
import { Modal } from "./Modal";

interface PasswordConfirmModalProps {
  title: string;
  description: string;
  confirmLabel?: string;
  /** When set, the user must type this exact phrase as well. */
  confirmPhrase?: string;
  danger?: boolean;
  busy?: boolean;
  onCancel: () => void;
  onConfirm: (password: string) => void;
}

/**
 * Re-authentication dialog for destructive actions. The server verifies the
 * password itself; this only collects it and (optionally) an exact-typing
 * confirmation such as REVOKE_ALL.
 */
export function PasswordConfirmModal({
  title,
  description,
  confirmLabel = "Confirm",
  confirmPhrase,
  danger = true,
  busy = false,
  onCancel,
  onConfirm,
}: PasswordConfirmModalProps) {
  const [password, setPassword] = useState("");
  const [phrase, setPhrase] = useState("");

  const ready =
    password.length > 0 && (!confirmPhrase || phrase === confirmPhrase) && !busy;

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (ready) onConfirm(password);
  };

  return (
    <Modal title={title} onClose={onCancel}>
      <form className="stack" onSubmit={submit}>
        <p className="t-sub muted">{description}</p>
        <div className="field">
          <label htmlFor="confirm-password">Your password</label>
          <input
            id="confirm-password"
            className="input"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </div>
        {confirmPhrase && (
          <div className="field">
            <label htmlFor="confirm-phrase">
              Type <code className="t-mono">{confirmPhrase}</code> to confirm
            </label>
            <input
              id="confirm-phrase"
              className="input"
              type="text"
              autoComplete="off"
              spellCheck={false}
              value={phrase}
              onChange={(event) => setPhrase(event.target.value)}
              required
            />
          </div>
        )}
        <div className="modal-actions">
          <button type="button" className="btn btn-ghost" onClick={onCancel}>
            Cancel
          </button>
          <button
            type="submit"
            className={danger ? "btn btn-danger" : "btn btn-primary"}
            disabled={!ready}
          >
            {busy ? "Working…" : confirmLabel}
          </button>
        </div>
      </form>
    </Modal>
  );
}