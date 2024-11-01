import { cn } from "@/lib/utils";
import React, { PropsWithChildren } from "react";

type Props = React.HTMLAttributes<HTMLDivElement>;

export const Container: React.FC<PropsWithChildren<Props>> = ({
  children,
  className,
  ...props
}) => {
  return (
    <div
      className={cn("flex flex-col p-4 md:p-6 w-full h-full", className)}
      {...props}
    >
      {children}
    </div>
  );
};
