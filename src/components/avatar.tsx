const SIZES = {
  sm: "h-8 w-8 text-xs",
  md: "h-10 w-10 text-sm",
};

/** The user's profile photo, or their initial when there's no photo. */
export function Avatar({
  name,
  image,
  size = "md",
}: {
  name: string;
  image: string | null | undefined;
  size?: keyof typeof SIZES;
}) {
  const box = SIZES[size];
  return image ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={image} alt="" referrerPolicy="no-referrer" className={`${box} shrink-0 rounded-full ring-1 ring-card-border`} />
  ) : (
    <span className={`${box} flex shrink-0 items-center justify-center rounded-full bg-wash font-semibold text-foreground`}>
      {name.charAt(0)}
    </span>
  );
}
