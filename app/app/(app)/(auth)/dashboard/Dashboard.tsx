"use client";

import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { serverAtom } from "@/lib/atoms/serverAtom";
import { useQuery } from "@tanstack/react-query";
import { useAtomValue } from "jotai/react";
import { MostPopularItem } from "./MostPopularItem";
import { NoStatsModal } from "./NoStatsModal";
import { WatchTimeGraph } from "./WatchTimeGraph";

export const Dashboard = () => {
  const server = useAtomValue(serverAtom);
  const { data } = useQuery({
    queryKey: ["statistics"],
    queryFn: async () => {
      if (!server) return;
      const res = await fetch(`/api/${server.id}/statistics`);
      return res.json();
    },
  });

  return (
    <Container>
      <PageTitle title="Statistics" />
      {data?.most_watched_item && data.watchtime_per_day ? (
        <div className="flex flex-col gap-6">
          <MostPopularItem data={data.most_watched_item} />
          <WatchTimeGraph data={data.watchtime_per_day} />
        </div>
      ) : (
        <NoStatsModal />
      )}
    </Container>
  );
};
