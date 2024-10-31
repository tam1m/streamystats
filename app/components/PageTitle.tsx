interface PageTitleProps {
  title: string;
  subtitle?: string;
}

export const PageTitle: React.FC<PageTitleProps> = ({ title, subtitle }) => {
  return (
    <div className="flex flex-col mb-6">
      <h1 className="font-bold text-3xl">{title}</h1>
      {subtitle && <p className="text-neutral-500 text-sm">{subtitle}</p>}
    </div>
  );
};
