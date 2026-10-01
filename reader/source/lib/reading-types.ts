export type ReadingProgress = {
  book: string;
  tl: string;
  slug: number;
  scroll: number;
  scrollRatio: number;
  pageIndex: number;
  updatedAt: number;
};

export type PageReadEvent = {
  book: string;
  tl: string;
  slug: number;
  pageIndex: number;
  /** Local calendar day in YYYY-MM-DD format; the server maps it to DATE. */
  date: string;
};

export type ReadingStateResponse = {
  progress: ReadingProgress[];
  daily: Record<string, number>;
  /** Lifetime count of unique chapter slugs reached, keyed by book and translation. */
  chapters?: Record<string, number>;
};
