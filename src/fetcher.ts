import pLimit from "p-limit";
// import pMemoize from "p-memoize";
const limit = pLimit(4);
export const clearWaitingRequests = limit.clearQueue;
export const fetcher: typeof fetch = // pMemoize
  (...args) => limit(() => fetch(...args));
