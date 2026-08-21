import Image from "next/image";

export function BrandMark({ className }: { className?: string }) {
  return (
    <Image
      aria-hidden="true"
      alt=""
      className={className}
      height={36}
      loading="eager"
      src="/icon.svg"
      width={36}
    />
  );
}
