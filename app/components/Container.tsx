import React, { PropsWithChildren } from "react";

type Props = React.HTMLAttributes<HTMLDivElement>;

export const Container: React.FC<PropsWithChildren<Props>> = ({
  children,
  ...props
}) => {
  return (
    <div className="flex flex-col p-6 w-full" {...props}>
      {children}
    </div>
  );
};
