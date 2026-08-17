import styles from "./github-link.module.css";

const configuredUrl = process.env.NEXT_PUBLIC_GITHUB_URL?.trim();
const githubUrl = configuredUrl?.startsWith("https://github.com/") ? configuredUrl : "";

export function GitHubLink() {
  if (!githubUrl) return null;

  return (
    <a
      className={styles.link}
      href={githubUrl}
      target="_blank"
      rel="noopener noreferrer"
      data-site-github="true"
      aria-label="在 GitHub 查看 TinyAI 源代码（新窗口）"
      title="GitHub"
    >
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M12 .7a11.5 11.5 0 0 0-3.64 22.41c.58.11.79-.25.79-.56v-2.23c-3.22.7-3.9-1.37-3.9-1.37-.52-1.34-1.28-1.7-1.28-1.7-1.05-.72.08-.71.08-.71 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.57-.29-5.27-1.29-5.27-5.68 0-1.25.45-2.28 1.19-3.08-.12-.29-.52-1.46.11-3.04 0 0 .97-.31 3.16 1.18a10.93 10.93 0 0 1 5.75 0c2.19-1.49 3.16-1.18 3.16-1.18.63 1.58.23 2.75.11 3.04.74.8 1.19 1.83 1.19 3.08 0 4.4-2.71 5.38-5.29 5.67.42.36.79 1.06.79 2.15v3.19c0 .31.21.68.8.56A11.5 11.5 0 0 0 12 .7Z" />
      </svg>
    </a>
  );
}
