interface PageTitleProps {
  title: string;
}

export const PageTitle: React.FC<PageTitleProps> = ({ title }) => {
  return <h1 className="font-bold text-3xl mb-6">{title}</h1>;
};
