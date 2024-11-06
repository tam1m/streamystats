"use client";

import * as React from "react";
import {
  ColumnDef,
  ColumnFiltersState,
  SortingState,
  VisibilityState,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
} from "@tanstack/react-table";
import { ArrowUpDown, ChevronDown, MoreHorizontal } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ItemWatchStats, Server } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import { useQuery } from "@tanstack/react-query";
import { Spinner } from "@/components/Spinner";
import { Skeleton } from "@/components/ui/skeleton";
import { useDebounce } from "use-debounce";
import router from "next/router";

export interface ItemWatchStatsTableProps {
  server: Server;
}

type Response = {
  page: number;
  per_page: number;
  total_items: number;
  total_pages: number;
  data: ItemWatchStats[];
};

export function ItemWatchStatsTable({ server }: ItemWatchStatsTableProps) {
  const [page, setPage] = React.useState<number>(1);
  const [search, setSearch] = React.useState<string>("");
  const [dSearch] = useDebounce(search, 1000);
  const [sorting, setSorting] = React.useState<SortingState>([]);
  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>(
    []
  );
  const [columnVisibility, setColumnVisibility] =
    React.useState<VisibilityState>({});

  const { data, isFetching, isLoading, refetch } = useQuery<Response>({
    queryKey: ["item-watch-stats", server.id, page, dSearch, sorting],
    queryFn: async () => {
      const queryParams = new URLSearchParams({
        page: page.toString(),
      });

      if (dSearch) {
        queryParams.append("search", dSearch);
      }

      if (sorting.length > 0) {
        queryParams.append("sort_by", sorting[0].id as string);
        queryParams.append("sort_order", sorting[0].desc ? "desc" : "asc");
        console.log(sorting[0].desc ? "desc" : "asc");
      }

      const res = await fetch(
        `/api/servers/${server.id}/statistics/items?${queryParams.toString()}`
      );
      const data = (await res.json()) as Response;
      console.log(data.total_pages, data.total_items, data.page);
      return data as Response;
    },
  });

  const columns: ColumnDef<ItemWatchStats>[] = [
    {
      accessorFn: (row) => row.item.name,
      id: "name",
      header: "Name",
      cell: ({ row }) => (
        <div className="capitalize">{row.getValue("name")}</div>
      ),
    },
    {
      accessorFn: (row) => row.item.type,
      id: "type",
      header: "Type",
      cell: ({ row }) => <div>{row.getValue("type")}</div>,
    },
    {
      accessorFn: (row) => row.item.production_year,
      id: "production_year",
      header: "Year",
      cell: ({ row }) => <div>{row.getValue("production_year")}</div>,
    },
    {
      accessorFn: (row) => row.item.series_name,
      id: "series_name",
      header: "Series",
      cell: ({ row }) => <div>{row.getValue("series_name") || "-"}</div>,
    },
    {
      accessorFn: (row) => row.item.season_name,
      id: "season_name",
      header: "Season",
      cell: ({ row }) => <div>{row.getValue("season_name") || "-"}</div>,
    },
    {
      accessorKey: "watch_count",
      header: ({ column }) => {
        return (
          <Button
            variant="ghost"
            // onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            onClick={() => {
              setSorting((prev) => {
                if (prev.length === 0 || prev[0].id !== "watch_count")
                  return [{ id: "watch_count", desc: false }];
                return [{ id: "watch_count", desc: !prev[0].desc }];
              });
            }}
          >
            Watch Count
            <ArrowUpDown className="ml-2 h-4 w-4" />
          </Button>
        );
      },
      cell: ({ row }) => (
        <div className="text-right font-medium">
          {row.getValue("watch_count")}
        </div>
      ),
    },
    {
      accessorKey: "total_watch_time",
      header: ({ column }) => {
        return (
          <Button
            variant="ghost"
            // onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            onClick={() => {
              setSorting((prev) => {
                if (prev.length === 0 || prev[0].id !== "total_watch_time")
                  return [{ id: "total_watch_time", desc: false }];
                return [{ id: "total_watch_time", desc: !prev[0].desc }];
              });
            }}
          >
            Total Watch Time
            <ArrowUpDown className="ml-2 h-4 w-4" />
          </Button>
        );
      },
      cell: ({ row }) => {
        const totalWatchTime = row.getValue("total_watch_time") as number;
        const formatted = formatDuration(totalWatchTime);
        return <div className="text-right font-medium">{formatted}</div>;
      },
    },
    {
      id: "actions",
      enableHiding: false,
      cell: ({ row }) => {
        const playbackActivity = row.original;

        return (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="h-8 w-8 p-0">
                <span className="sr-only">Open menu</span>
                <MoreHorizontal className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuLabel>Actions</DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => {
                  window.open(
                    `${server.url}/web/#/details?id=${playbackActivity.item_id}`,
                    "_blank"
                  );
                }}
              >
                Open in Jellyfin
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        );
      },
    },
  ];

  const table = useReactTable({
    data: data?.data || [],
    columns,
    onColumnFiltersChange: setColumnFilters,
    getCoreRowModel: getCoreRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    onColumnVisibilityChange: setColumnVisibility,
    state: {
      columnFilters,
      columnVisibility,
    },
    manualPagination: true,
    pageCount: data?.total_pages || -1,
  });

  return (
    <div className="w-full">
      <div className="flex items-center py-4">
        <Input
          placeholder="Search items..."
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="max-w-sm"
        />
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" className="ml-auto">
              Columns <ChevronDown className="ml-2 h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {table
              .getAllColumns()
              .filter((column) => column.getCanHide())
              .map((column) => {
                return (
                  <DropdownMenuCheckboxItem
                    key={column.id}
                    className="capitalize"
                    checked={column.getIsVisible()}
                    onCheckedChange={(value) =>
                      column.toggleVisibility(!!value)
                    }
                  >
                    {column.id}
                  </DropdownMenuCheckboxItem>
                );
              })}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      {isFetching || isLoading ? (
        <div className="">
          <Skeleton className="w-full h-12 mb-4" />
          <Skeleton className="w-full h-64 mb-4" />
          <Skeleton className="w-full h-64" />
        </div>
      ) : (
        <>
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                {table.getHeaderGroups().map((headerGroup) => (
                  <TableRow key={headerGroup.id}>
                    {headerGroup.headers.map((header) => {
                      return (
                        <TableHead key={header.id}>
                          {header.isPlaceholder
                            ? null
                            : flexRender(
                                header.column.columnDef.header,
                                header.getContext()
                              )}
                        </TableHead>
                      );
                    })}
                  </TableRow>
                ))}
              </TableHeader>
              <TableBody>
                {table.getRowModel().rows?.length ? (
                  table.getRowModel().rows.map((row) => (
                    <TableRow
                      key={row.id}
                      data-state={row.getIsSelected() && "selected"}
                    >
                      {row.getVisibleCells().map((cell) => (
                        <TableCell key={cell.id}>
                          {flexRender(
                            cell.column.columnDef.cell,
                            cell.getContext()
                          )}
                        </TableCell>
                      ))}
                    </TableRow>
                  ))
                ) : (
                  <TableRow>
                    <TableCell
                      colSpan={columns.length}
                      className="h-24 text-center"
                    >
                      No results.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </>
      )}
      <div className="flex items-center justify-between space-x-2 py-4">
        {isLoading || isFetching ? (
          <div>
            <Skeleton className="w-24 h-8" />
          </div>
        ) : (
          <div>
            <p className="text-sm text-neutral-500">
              {((data?.page || 0) - 1) * 20 + 1} -{" "}
              {((data?.page || 0) - 1) * 20 + (data?.data.length || 0)} of{" "}
              {data?.total_items} results.
            </p>
          </div>
        )}
        <div className="space-x-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              setPage((old) => Math.max(old - 1, 1));
            }}
            disabled={page === 1}
          >
            Previous
          </Button>
          <Button
            disabled={page === data?.total_pages}
            variant="outline"
            size="sm"
            onClick={() => {
              setPage((old) => old + 1);
            }}
          >
            Next
          </Button>
        </div>
      </div>
    </div>
  );
}
