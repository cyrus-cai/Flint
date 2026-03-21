import path from "path";
import fs from "fs";
import { Feed } from "feed";

const MDX_DIR = "changelogs";

export const generateRssFeed = async () => {
  const siteURL = "https://flintapp.dev";
  const date = new Date();
  const author = {
    name: "Flint",
    link: "https://flintapp.dev",
  };

  const feed = new Feed({
    title: "Flint Changelog",
    description: "What's new in Flint",
    id: siteURL,
    link: siteURL,
    image: `${siteURL}/favicon.ico`,
    favicon: `${siteURL}/favicon.ico`,
    copyright: `All rights reserved ${date.getFullYear()}, Flint`,
    updated: date,
    generator: "Feed for Flint changelog",
    feedLinks: {
      rss2: `${siteURL}/rss/feed.xml`, // xml format
      json: `${siteURL}/rss/feed.json`, // json fromat
    },
    author,
  });

  const changelogFileObjects = fs.readdirSync(path.join(process.cwd(), "pages", MDX_DIR), {
    withFileTypes: true,
  });

  const changelogFiles = await Promise.allSettled(
    changelogFileObjects.map((file) => import(`../pages/changelogs/${file.name}`))
  );

  const changelogsMeta = changelogFiles
    .map((res) => res.status === "fulfilled" && res.value.meta)
    .filter((item) => item)
    .sort((a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime());

  changelogsMeta.forEach((changelog) => {
    const { title, description, content, publishedAt, slug, headerImage } = changelog;
    const url = `${siteURL}/changelogs/${slug}`;
    
    // Convert relative paths to absolute URLs for RSS feed
    const absoluteHeaderImage = headerImage?.startsWith('/') 
      ? `${siteURL}${headerImage}` 
      : headerImage;
    
    feed.addItem({
      title: title,
      id: url,
      link: url,
      description: description,
      content: content,
      image: absoluteHeaderImage,
      date: new Date(publishedAt),
    });
  });

  console.debug("-------------------");
  console.debug("Generating RSS feed");
  console.debug("-------------------");
  const Rssfeed = feed.rss2();

  console.debug("-------------------");
  console.debug("Writing RSS feed to public/rss.xml");
  console.debug("-------------------");

  fs.writeFileSync("./public/rss.xml", Rssfeed, "utf8");
};
