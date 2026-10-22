import { useEffect, useId, useRef, type ReactNode } from "react";

interface ModalProps {
  title: string;
  children: ReactNode;
  onClose: () => void;
}

/** Accessible modal dialog: Esc closes, focus moves in, scrim click closes. */
export function Modal({ title, children, onClose }: ModalProps) {
  const titleId = useId();
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    const focusable = ref.current?.querySelector<HTMLElement>(
      "input, button, select, textarea, [tabindex]",
    );
    focusable?.focus();
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      className="modal-scrim"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        ref={ref}
      >
        <h2 id={titleId} className="t-title3">
          {title}
        </h2>
        {children}
      </div>
    </div>
  );
}