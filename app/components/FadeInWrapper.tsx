import { PropsWithChildren } from "react";

export const FadeInWrapper: React.FC<PropsWithChildren> = ({ children }) => {
  return <div className="fade-in">{children}</div>;
};
