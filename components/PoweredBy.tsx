// Footer shown on every screen: "Powered By : KMR Group of Companies" with the name linking to the website.
// Another deployment can change it with POWERED_BY_TEXT / POWERED_BY_URL (POWERED_BY_TEXT=off hides it).
export function PoweredBy() {
  const name = process.env.POWERED_BY_TEXT || "KMR Group of Companies";
  const url = process.env.POWERED_BY_URL || "https://www.kmr-groups.com";
  if (name.toLowerCase() === "off") return null;
  return (
    <footer className="powered-by">
      <span>Powered By : <a href={url} target="_blank" rel="noopener">{name}</a></span>
    </footer>
  );
}
