import React from "react";
import { useRouter } from "next/router";
import useTimelineStore from "lib/state/use-timeline-store";
import { IAggregatedChangelogs, IImagePreviewMeta } from "lib/models/view";
import { getArticleSlugs } from "lib/get-articles-slugs";
import { generateRssFeed } from "lib/generate-rss-feed";
import { generateLatestChangelogsJson } from "lib/generate-latest-json";
import Years from "components/layout/years";
import Weeks from "components/layout/weeks";
import Months from "components/layout/months";
import { MainLayout } from "components/layout/main-layout";
import { TabPanel, TabPanels, Tabs } from "@chakra-ui/react";

const ITEMS_PER_PAGE = 4;

export interface IPageProps {
  allSlugs: string[];
  allChangelogsMap: { months: IAggregatedChangelogs; years: IAggregatedChangelogs };
  totalItems: { weeks: number; months: number; years: number };
}

const Page = ({ allSlugs, allChangelogsMap, totalItems }: IPageProps) => {
  const timeline = useTimelineStore();
  
  const [displayedItems, setDisplayedItems] = React.useState(ITEMS_PER_PAGE);

  const loadMore = () => {
    setDisplayedItems((prev) => prev + ITEMS_PER_PAGE);
  };

  const hasMore = displayedItems < totalItems[timeline.view];

  React.useEffect(() => {
    if (typeof window !== "undefined") {
      window.scrollTo({
        top: 0,
        behavior: "smooth",
      });
    }
    setDisplayedItems(ITEMS_PER_PAGE);
  }, [timeline.view]);

  const displayedSlugs = allSlugs.slice(0, displayedItems);
  
  const displayedMonthsMap = React.useMemo(() => {
    const keys = Object.keys(allChangelogsMap.months).slice(0, displayedItems);
    return keys.reduce((acc, key) => {
      acc[key] = allChangelogsMap.months[key];
      return acc;
    }, {} as IAggregatedChangelogs);
  }, [allChangelogsMap.months, displayedItems]);

  const displayedYearsMap = React.useMemo(() => {
    const keys = Object.keys(allChangelogsMap.years).slice(0, displayedItems);
    return keys.reduce((acc, key) => {
      acc[key] = allChangelogsMap.years[key];
      return acc;
    }, {} as IAggregatedChangelogs);
  }, [allChangelogsMap.years, displayedItems]);

  const currentDataLength = React.useMemo(() => {
    if (timeline.view === "weeks") {
      return displayedSlugs.length;
    } else if (timeline.view === "months") {
      return Object.keys(displayedMonthsMap).length;
    } else {
      return Object.keys(displayedYearsMap).length;
    }
  }, [timeline.view, displayedSlugs.length, displayedMonthsMap, displayedYearsMap]);

  return (
    <MainLayout
      itemsPerPage={ITEMS_PER_PAGE}
      totalItems={{
        weeks: totalItems.weeks,
        months: totalItems.months,
        years: totalItems.years,
      }}
      hasMore={hasMore}
      loadMore={loadMore}
      currentDataLength={currentDataLength}
    >
      <Tabs
        isLazy
        lazyBehavior="keepMounted"
        isFitted
        index={timeline.view === "weeks" ? 0 : timeline.view === "months" ? 1 : 2}
        onChange={(index) => {
          if (index === 0) {
            timeline.setView("weeks");
          } else if (index === 1) {
            timeline.setView("months");
          } else if (index === 2) {
            timeline.setView("years");
          }
        }}
      >
        <TabPanels>
          <TabPanel padding={0}>
            <Weeks slugs={displayedSlugs} />
          </TabPanel>
          <TabPanel padding={0}>
            <Months monthChangelogsMap={displayedMonthsMap} />
          </TabPanel>
          <TabPanel padding={0}>
            <Years yearChangelogsMap={displayedYearsMap} />
          </TabPanel>
        </TabPanels>
      </Tabs>
    </MainLayout>
  );
};

export async function getStaticProps({ params }) {
  await generateRssFeed();
  await generateLatestChangelogsJson();
  const slugs = getArticleSlugs();

  const results = await Promise.allSettled(slugs.map((slug) => import(`./changelogs/${slug}.mdx`)));

  const meta = results
    .map((res) => res.status === "fulfilled" && res.value.meta)
    .filter((item) => item);

  meta.sort((a, b) => {
    const dateB = new Date(b.publishedAt);
    const dateA = new Date(a.publishedAt);
    return dateB.getTime() - dateA.getTime();
  });

  const monthChangelogsMap: IAggregatedChangelogs = meta.reduce((acc, item, index) => {
    const date = new Date(item.publishedAt);
    const year = date.getFullYear();
    const month = date.getMonth() + 1;
    const key = `${year}-${month}`;
    if (!acc[key]) {
      acc[key] = [];
    }
    acc[key].push({
      imageUrl: item.headerImage,
      slug: item.slug,
      publishedAt: item.publishedAt,
      weeklyViewPage: Math.floor(index / ITEMS_PER_PAGE),
    } as IImagePreviewMeta);
    return acc;
  }, {});

  const yearsChangelogsMap: IAggregatedChangelogs = meta.reduce((acc, item, index) => {
    const date = new Date(item.publishedAt);
    const year = date.getFullYear().toString();
    if (!acc[year]) {
      acc[year] = [];
    }

    acc[year].push({
      imageUrl: item.headerImage,
      slug: item.slug,
      publishedAt: item.publishedAt,
      weeklyViewPage: Math.floor(index / ITEMS_PER_PAGE),
      monthlyViewPage: Math.floor(
        (Object.keys(monthChangelogsMap)
          .sort((a, b) => new Date(b).getTime() - new Date(a).getTime())
          .indexOf(`${year}-${date.getMonth() + 1}`) +
          1) /
          ITEMS_PER_PAGE
      ),
    } as IImagePreviewMeta);
    return acc;
  }, {});

  return {
    props: {
      allSlugs: meta.map((item) => item.slug),
      allChangelogsMap: { months: monthChangelogsMap, years: yearsChangelogsMap },
      totalItems: {
        weeks: slugs.length,
        months: Object.keys(monthChangelogsMap).length,
        years: Object.keys(yearsChangelogsMap).length,
      },
    },
    revalidate: 1,
  };
}

export default Page;
