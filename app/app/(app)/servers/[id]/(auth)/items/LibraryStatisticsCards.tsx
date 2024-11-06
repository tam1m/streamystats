import { type LibraryStatistics } from "@/lib/db";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Film, Tv, Folder, Users, PlaySquare } from "lucide-react";

interface Props {
  data: LibraryStatistics;
}

export const LibraryStatisticsCards: React.FC<Props> = ({ data }) => {
  const stats = [
    { title: "Movies", value: data.movies_count, icon: Film },
    { title: "Episodes", value: data.episodes_count, icon: PlaySquare },
    { title: "Series", value: data.series_count, icon: Tv },
    { title: "Libraries", value: data.libraries_count, icon: Folder },
    { title: "Users", value: data.users_count, icon: Users },
  ];
  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-5">
      {stats.map((item) => (
        <Card key={item.title}>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">{item.title}</CardTitle>
            <item.icon className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{formatNumber(item.value)}</div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
};

/**
 * Adds spaces 1000s separator to a number.
 */
function formatNumber(num: number): string {
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}
