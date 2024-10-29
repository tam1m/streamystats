import { atomWithStorage } from "jotai/utils";
import { Server } from "../db";

export const serverAtom = atomWithStorage<Server | null>(
  "selectedServer",
  null
);
