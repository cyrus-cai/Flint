const fs = require("fs");
const path = require("path");

function extractMetaFromMdx(content) {
  const slugMatch = content.match(/slug:\s*["']([^"']+)["']/);
  const publishedAtMatch = content.match(/publishedAt:\s*["']([^"']+)["']/);
  const titleMatch = content.match(/title:\s*["']([^"']+)["']/);
  const headerImageMatch = content.match(/headerImage:\s*["']([^"']+)["']/);
  
  if (!slugMatch || !publishedAtMatch || !titleMatch) return null;
  
  const authorsMatch = content.match(/authors:\s*\[([\s\S]*?)\]/);
  let authors = [];
  if (authorsMatch) {
    const nameMatch = authorsMatch[1].match(/name:\s*["']([^"']+)["']/);
    const descMatch = authorsMatch[1].match(/description:\s*["']([^"']+)["']/);
    const avatarMatch = authorsMatch[1].match(/avatarUrl:\s*["']([^"']+)["']/);
    
    if (nameMatch) {
      authors.push({
        name: nameMatch[1],
        description: descMatch ? descMatch[1] : "",
        avatarUrl: avatarMatch ? avatarMatch[1] : ""
      });
    }
  }
  
  return {
    slug: slugMatch[1],
    publishedAt: publishedAtMatch[1],
    title: titleMatch[1],
    headerImage: headerImageMatch ? headerImageMatch[1] : "",
    authors: authors
  };
}

function generateLatestJson() {
  const changelogDir = path.join(process.cwd(), "pages", "changelogs");
  const changelogFiles = fs.readdirSync(changelogDir, { withFileTypes: true });

  const changelogsMeta = [];

  for (const file of changelogFiles) {
    if (!file.name.endsWith('.mdx')) continue;
    
    try {
      const filePath = path.join(changelogDir, file.name);
      const content = fs.readFileSync(filePath, 'utf8');
      const meta = extractMetaFromMdx(content);
      
      if (meta) {
        changelogsMeta.push(meta);
      }
    } catch (error) {
      console.error(`Error loading ${file.name}:`, error.message);
    }
  }

  const sortedChangelogs = changelogsMeta
    .sort((a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime())
    .slice(0, 3);

  const outputPath = path.join(process.cwd(), "public", "latest.json");
  fs.writeFileSync(outputPath, JSON.stringify(sortedChangelogs), "utf8");
  
  console.log(`✅ Generated latest.json with ${sortedChangelogs.length} entries`);
  sortedChangelogs.forEach(c => console.log(`   - ${c.title}`));
}

generateLatestJson();
