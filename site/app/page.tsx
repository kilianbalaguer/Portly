import { CopyCommand } from "./CopyCommand";
import { downloadURL, site } from "./site";

const features = [
  {
    icon: "◎",
    title: "Sees everything",
    body: "Every listening server with its port, project, framework, memory, uptime and pid. System noise stays hidden until you ask.",
  },
  {
    icon: "✦",
    title: "Knows your stack",
    body: "Recognises Next.js, Vite, Django, Rails and friends from the command line or the project's dependencies.",
  },
  {
    icon: "↻",
    title: "Restarts done right",
    body: "Re-runs the original command, in its folder, through your login shell, so nvm, asdf and pyenv just work.",
  },
  {
    icon: "≡",
    title: "Live logs",
    body: "Servers Portly starts have their output captured: the last 5,000 lines, with follow, filter and copy.",
  },
  {
    icon: "⌘",
    title: "Keyboard first",
    body: "⌃⌥L opens Portly from anywhere with search focused. Type a few letters, press ↩, and it's open in your browser.",
  },
  {
    icon: "◐",
    title: "Private by design",
    body: "No network, no analytics, no accounts, and no Accessibility or Screen Recording permission. It all stays on your Mac.",
  },
];

const frameworks = [
  "Next.js", "Vite", "Nuxt", "Remix", "Astro", "SvelteKit", "Angular", "Express", "NestJS",
  "Django", "FastAPI", "Flask", "Rails", "Laravel", "Phoenix", "Hugo",
];

const faqs = [
  {
    q: "Why can't I see logs for a server I started in my terminal?",
    a: "macOS doesn't let one app read another app's terminal output. Portly captures logs for servers it starts, and offers a one-click “Restart in Portly” for everything else.",
  },
  {
    q: "Will a restart lose my environment variables?",
    a: "Anything in your shell profile comes back, including version managers. Only variables typed by hand into that one terminal session can't be recovered, and Portly tells you before restarting.",
  },
  {
    q: "Why does macOS warn me the first time I open it?",
    a: "This build isn't notarized by Apple yet. Click Open Anyway in System Settings → Privacy & Security, or run the command above. It's a one-time step.",
  },
  {
    q: "Is it really free?",
    a: "Yes. Portly is MIT-licensed and the full source is on GitHub.",
  },
];

function Keys({ keys }: { keys: string[] }) {
  return (
    <span className="keys" aria-label={keys.join(" ")}>
      {keys.map((key) => (
        <kbd key={key}>{key}</kbd>
      ))}
    </span>
  );
}

export default function Home() {
  return (
    <>
      <div className="glow" aria-hidden />

      <header className="nav wrap">
        <a href="#" className="brand">
          <img src="/logo.png" alt="" width={28} height={28} />
          Portly
        </a>
        <nav>
          <a href="#features">Features</a>
          <a href="#install">Install</a>
          <a href="#faq">FAQ</a>
          <a href={site.repo} className="nav-github">GitHub ↗</a>
        </nav>
      </header>

      <main>
        <section className="hero wrap">
          <a className="eyebrow" href={`${site.repo}/releases/tag/v${site.version}`}>
            <span className="dot" /> v{site.version} · free &amp; open source
          </a>
          <h1>
            Every dev server on your Mac,
            <br />
            <span className="accent">one keystroke away.</span>
          </h1>
          <p className="lede">
            Portly lives in your menu bar and shows what&apos;s running on every port: which project, which
            framework, how long it&apos;s been up. Open, stop, restart or tail any of them in a click.
          </p>
          <div className="actions">
            <a className="button primary" href={downloadURL}>
              <AppleIcon /> Download for macOS
            </a>
            <a className="button" href={site.repo}>
              View on GitHub
            </a>
          </div>
          <p className="meta">
            macOS 14+ · Apple Silicon &amp; Intel · {site.size} · then press <Keys keys={["⌃", "⌥", "L"]} />
          </p>

          <figure className="shot">
            <img src="/hero-ui.png" width={1180} height={1000} alt="Portly listing storefront on port 3000 (Next.js), dashboard on 5173 (Vite) and api on 8000 (Django), with captured logs" />
          </figure>
        </section>

        <section className="demo wrap">
          <div className="demo-copy">
            <h2>Find it. Open it. Done.</h2>
            <ol className="steps">
              <li>
                <Keys keys={["⌃", "⌥", "L"]} />
                <span>Portly opens from anywhere, search focused.</span>
              </li>
              <li>
                <span className="step-key">store</span>
                <span>Type a port, project or framework.</span>
              </li>
              <li>
                <Keys keys={["↩"]} />
                <span>It&apos;s open in your browser.</span>
              </li>
            </ol>
            <p className="muted">
              Need a fresh start? Restart re-runs <code>npm run dev</code> in the right folder and captures its
              logs from then on.
            </p>
          </div>
          <figure className="demo-shot">
            <img src="/demo.gif" alt="Typing “store” filters the list; restarting shows Stopping…, Starting…, then live logs" width={520} height={520} />
          </figure>
        </section>

        <section id="features" className="wrap">
          <h2 className="center">Small app. Sharp tools.</h2>
          <div className="grid">
            {features.map((feature) => (
              <article key={feature.title} className="card">
                <span className="card-icon" aria-hidden>
                  {feature.icon}
                </span>
                <h3>{feature.title}</h3>
                <p>{feature.body}</p>
              </article>
            ))}
          </div>
          <ul className="chips" aria-label="Detected frameworks">
            {frameworks.map((name) => (
              <li key={name}>{name}</li>
            ))}
            <li className="chip-more">and more</li>
          </ul>
        </section>

        <section id="install" className="install wrap">
          <h2 className="center">Install in a minute</h2>
          <ol className="install-steps">
            <li>
              <strong>Download</strong> <a href={downloadURL}>Portly-{site.version}.dmg</a>
            </li>
            <li>
              <strong>Drag</strong> Portly into Applications
            </li>
            <li>
              <strong>Launch</strong> it. It lives in your menu bar.
            </li>
          </ol>
          <div className="note">
            <p>
              <strong>First launch:</strong> Portly isn&apos;t notarized by Apple yet, so macOS asks first. Click{" "}
              <em>Open Anyway</em> in System Settings → Privacy &amp; Security, or run:
            </p>
            <CopyCommand command="xattr -dr com.apple.quarantine /Applications/Portly.app" />
          </div>
        </section>

        <section id="faq" className="faq wrap">
          <h2 className="center">Questions</h2>
          {faqs.map((faq) => (
            <details key={faq.q}>
              <summary>{faq.q}</summary>
              <p>{faq.a}</p>
            </details>
          ))}
        </section>

        <section className="cta wrap">
          <img src="/logo.png" alt="" width={72} height={72} />
          <h2>Stop hunting through terminals.</h2>
          <a className="button primary" href={downloadURL}>
            <AppleIcon /> Download Portly {site.version}
          </a>
        </section>
      </main>

      <footer className="footer wrap">
        <span>© 2026 Kilian Balaguer · MIT License</span>
        <span>
          <a href={site.repo}>Source</a> · <a href={`${site.repo}/releases`}>Releases</a> ·{" "}
          <a href={`${site.repo}/issues`}>Report an issue</a>
        </span>
      </footer>
    </>
  );
}

function AppleIcon() {
  return (
    <svg width="15" height="18" viewBox="0 0 814 1000" aria-hidden fill="currentColor">
      <path d="M788 341c-6 4-108 62-108 190 0 148 130 200 134 202-1 3-21 72-69 141-43 62-88 124-156 124s-86-40-165-40c-77 0-104 41-166 41s-106-57-156-127C45 789 0 667 0 551 0 365 121 266 240 266c63 0 116 42 156 42 38 0 97-44 169-44 27 0 126 2 192 77zM552 168c30-35 51-84 51-133 0-7-1-14-2-19-49 2-107 33-142 73-27 31-53 80-53 130 0 8 1 15 2 18 3 1 8 1 13 1 44 0 99-29 131-70z" />
    </svg>
  );
}
