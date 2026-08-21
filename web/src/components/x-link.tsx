import styles from "./github-link.module.css";

function validatedXUrl(value: string | undefined) {
  if (!value) return "";
  try {
    const url = new URL(value.trim());
    const allowedHosts = new Set(["x.com", "www.x.com", "twitter.com", "www.twitter.com"]);
    return url.protocol === "https:" && allowedHosts.has(url.hostname.toLowerCase())
      ? url.toString()
      : "";
  } catch {
    return "";
  }
}

const xUrl = validatedXUrl(process.env.NEXT_PUBLIC_X_URL);

function XMark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231 5.451-6.231Zm-1.161 17.52h1.833L7.084 4.126H5.117L17.083 19.77Z" />
    </svg>
  );
}

export function XLink() {
  if (!xUrl) {
    return (
      <span
        className={`${styles.link} ${styles.disabled}`}
        data-site-x="pending"
        aria-label="TinyAI X 官方账号即将上线"
        title="X / Twitter（即将上线）"
      >
        <XMark />
      </span>
    );
  }

  return (
    <a
      className={styles.link}
      href={xUrl}
      target="_blank"
      rel="noopener noreferrer"
      data-site-x="true"
      aria-label="在 X 查看 TinyAI 官方账号（新窗口）"
      title="X / Twitter"
    >
      <XMark />
    </a>
  );
}
