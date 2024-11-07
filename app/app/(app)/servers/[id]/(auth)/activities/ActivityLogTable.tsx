"use client";

import {
  ColumnDef,
  ColumnFiltersState,
  VisibilityState,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  useReactTable,
} from "@tanstack/react-table";
import { ChevronDown, MoreHorizontal } from "lucide-react";
import * as React from "react";

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
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ActivitiesResponse, ActivityLogEntry, Server } from "@/lib/db";
import { useQuery } from "@tanstack/react-query";

export interface ActivityLogTableProps {
  server: Server;
}

export function ActivityLogTable({ server }: ActivityLogTableProps) {
  const [page, setPage] = React.useState<number>(1);
  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>(
    []
  );
  const [columnVisibility, setColumnVisibility] =
    React.useState<VisibilityState>({});

  const { data, isFetching, isLoading, refetch } = useQuery<ActivitiesResponse>(
    {
      queryKey: ["activity-log", server.id, page],
      queryFn: async () => {
        const queryParams = new URLSearchParams({
          page: page.toString(),
        });

        const res = await fetch(
          `/api/servers/${server.id}/activities?${queryParams.toString()}`
        );
        const data = (await res.json()) as ActivitiesResponse;
        return data;
      },
    }
  );

  const columns: ColumnDef<ActivityLogEntry>[] = [
    {
      accessorKey: "name",
      header: "Name",
      cell: ({ row }) => (
        <div className="capitalize">{row.getValue("name")}</div>
      ),
    },
    {
      accessorKey: "type",
      header: "Type",
      cell: ({ row }) => <div>{row.getValue("type")}</div>,
    },
    {
      accessorKey: "date",
      header: "Date",
      cell: ({ row }) => <div>{row.getValue("date")}</div>,
    },
    {
      accessorKey: "severity",
      header: "Severity",
      cell: ({ row }) => <div>{row.getValue("severity")}</div>,
    },
    {
      accessorKey: "short_overview",
      header: "Overview",
      cell: ({ row }) => <div>{row.getValue("short_overview")}</div>,
    },
    // {
    //   id: "actions",
    //   enableHiding: false,
    //   cell: ({ row }) => {
    //     const activityLog = row.original;

    //     return (
    //       <DropdownMenu>
    //         <DropdownMenuTrigger asChild>
    //           <Button variant="ghost" className="h-8 w-8 p-0">
    //             <span className="sr-only">Open menu</span>
    //             <MoreHorizontal className="h-4 w-4" />
    //           </Button>
    //         </DropdownMenuTrigger>
    //         <DropdownMenuContent align="end">
    //           <DropdownMenuLabel>Actions</DropdownMenuLabel>
    //           <DropdownMenuSeparator />
    //           <DropdownMenuItem
    //             onClick={() => {
    //               // Add action here
    //             }}
    //           >
    //             View Details
    //           </DropdownMenuItem>
    //         </DropdownMenuContent>
    //       </DropdownMenu>
    //     );
    //   },
    // },
  ];

  const table = useReactTable({
    data: data?.data || [],
    columns,
    onColumnFiltersChange: setColumnFilters,
    getCoreRowModel: getCoreRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
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
      <div className="flex items-center">
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
              {((data?.page || 0) - 1) * (data?.per_page || 0) + 1} -{" "}
              {((data?.page || 0) - 1) * (data?.per_page || 0) +
                (data?.data.length || 0)}{" "}
              of {data?.total_items} results.
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
