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
import { ChevronDown } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import * as React from "react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ActivitiesResponse, ActivityLogEntry, Server } from "@/lib/db";

export interface ActivityLogTableProps {
  server: Server;
  data: ActivitiesResponse;
}

export function ActivityLogTable({ server, data }: ActivityLogTableProps) {
  const router = useRouter();
  const searchParams = useSearchParams();

  // Get current page from URL query parameters or default to 1
  const currentPage = Number(searchParams.get("page") || "1");

  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>(
    []
  );
  const [columnVisibility, setColumnVisibility] =
    React.useState<VisibilityState>({});

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
      cell: ({ row }) => (
        <div>
          {new Date(row.getValue("date")).toLocaleString("en-UK", {
            dateStyle: "medium",
            timeStyle: "short",
          })}
        </div>
      ),
    },
    // {
    //   accessorKey: "severity",
    //   header: "Severity",
    //   cell: ({ row }) => <div>{row.getValue("severity")}</div>,
    // },
    // {
    //   accessorKey: "short_overview",
    //   header: "Overview",
    //   cell: ({ row }) => <div>{row.getValue("short_overview")}</div>,
    // },
    // {
    //   id: "actions",
    //   enableHiding: false,
    //   cell: ({ row }) => { ... }
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

  // Function to update URL with new page parameter
  const handlePageChange = (newPage: number) => {
    // Create a new URLSearchParams object from the current search params
    const params = new URLSearchParams(searchParams.toString());

    // Update or add the page parameter
    params.set("page", newPage.toString());

    // Update the URL without reloading the page
    router.push(`?${params.toString()}`, { scroll: false });
  };

  return (
    <div className="w-full">
      <div className="flex items-center mb-2">
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

      <div className="rounded-md border">
        <Table>
          <TableHeader className="">
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
      <div className="flex items-center justify-between space-x-2 py-4">
        <div>
          <p className="text-sm text-neutral-500">
            {((data?.page || 0) - 1) * (data?.per_page || 0) + 1} -{" "}
            {((data?.page || 0) - 1) * (data?.per_page || 0) +
              (data?.data?.length || 0)}{" "}
            of {data?.total_items} results.
          </p>
        </div>
        <div className="space-x-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => handlePageChange(currentPage - 1)}
            disabled={currentPage <= 1}
          >
            Previous
          </Button>
          <Button
            disabled={currentPage >= (data?.total_pages || 1)}
            variant="outline"
            size="sm"
            onClick={() => handlePageChange(currentPage + 1)}
          >
            Next
          </Button>
        </div>
      </div>
    </div>
  );
}
