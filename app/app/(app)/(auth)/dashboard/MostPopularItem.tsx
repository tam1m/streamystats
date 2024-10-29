import { Statistics } from "@/lib/db";
import { formatDuration } from "@/lib/utils";

interface Props {
  data: NonNullable<Statistics["most_watched_item"]>;
}

export const MostPopularItem: React.FC<Props> = ({ data }) => {
  return (
    <div className="border rounded-lg p-4 grid grid-rows-2 md:grid-rows-1 md:grid-cols-2 gap-4 items-center">
      <div>
        <p className="text-sm text-neutral-500">Most Popular Item</p>
        <p className="text-xl font-bold">{data.item_name}</p>
        <p className="text-sm text-neutral-500">{data.item_type}</p>
      </div>
      <div className="flex flex-col md:items-end">
        <p className="text-sm text-neutral-500">Watch time</p>
        <p className="text-xl font-bold">
          {formatDuration(data.total_play_duration)}
        </p>
        <p className="text-neutral-500 text-sm">
          Played {data.total_play_count} times
        </p>
      </div>
    </div>
  );
};
