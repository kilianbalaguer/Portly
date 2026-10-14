import type { Metadata, Viewport } from "next";
import "./globals.css";

const description =
  "A tiny native menu bar app that finds the dev servers running on your Mac and lets you open, stop, restart and tail them. Free and open source.";

export const metadata: Metadata = {
  // Set SITE_URL when deploying so social previews get absolute image URLs.
  metadataBase: new URL(process.env.SITE_URL ?? "http://localhost:3000"),
  title: "Portly — every dev server on your Mac, one keystroke away",
  description,
  openGraph: {
    title: "Portly",
    description,
    images: [{ url: "/hero.png", width: 2400, height: 1240, alt: "Portly listing dev servers in the menu bar" }],
  },
  twitter: { card: "summary_large_image", title: "Portly", description, images: ["/hero.png"] },
};

export const viewport: Viewport = {
  themeColor: "#0c0c16",
  colorScheme: "dark",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
