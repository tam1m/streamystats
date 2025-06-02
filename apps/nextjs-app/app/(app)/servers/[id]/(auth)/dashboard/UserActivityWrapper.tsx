import { getDefaultStartDate, setEndDateToEndOfDay } from "@/dates";
import { getUserActivityPerDay } from "@/lib/db/users";
import { Server } from "@streamystats/database";
import * as React from "react";
import { UserActivityChart } from "./UserActivityChart";

interface Props {
  server: Server;
  startDate: string;
  endDate: string;
}

export const UserActivityWrapper: React.FC<Props> = async ({
  server,
  startDate,
  endDate,
}) => {
  const _startDate = startDate || getDefaultStartDate();
  const _endDate = setEndDateToEndOfDay(endDate);

  const data = await getUserActivityPerDay(server.id, _startDate, _endDate);

  return <UserActivityChart data={data} />;
};
