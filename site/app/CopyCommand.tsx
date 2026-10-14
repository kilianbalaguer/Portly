"use client";

import { useState } from "react";

/** A one-line shell command with a copy button. */
export function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    } catch {
      // Clipboard can be unavailable (insecure context); the command stays selectable.
    }
  }

  return (
    <div className="command">
      <code>{command}</code>
      <button type="button" onClick={copy} aria-label="Copy command">
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}
