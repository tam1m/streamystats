export default async function ItemDetailsPage({
  params,
}: {
  params: Promise<{ id: string; itemId: string }>;
}) {
  const { id, itemId } = await params;

  return (
    <div>
      {/* <ItemDetails item={data.item} statistics={data.statistics} /> */}
    </div>
  );
}
