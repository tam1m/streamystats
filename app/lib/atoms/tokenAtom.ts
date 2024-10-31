import { atomWithStorage } from "jotai/utils";
import { Server } from "../db";

export const tokenAtom = atomWithStorage<string | null>("token", null);
