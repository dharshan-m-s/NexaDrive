import { describe, expect, it } from "vitest";
import {
  formatBytes,
  formatDuration,
  formatPercent,
  formatRelative,
} from "./format";

describe("formatBytes", () => {
  it("handles zero and missing values", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(null)).toBe("—");
    expect(formatBytes(undefined)).toBe("—");
  });

  it("uses binary units", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(1024)).toBe("1.0 KiB");
    expect(formatBytes(3 * 1024 ** 3)).toBe("3.0 GiB");
  });
});

describe("formatPercent", () => {
  it("renders digits and blanks", () => {
    expect(formatPercent(12.34, 1)).toBe("12.3%");
    expect(formatPercent(42)).toBe("42%");
    expect(formatPercent(null)).toBe("—");
  });
});

describe("formatDuration", () => {
  it("renders compact uptimes", () => {
    expect(formatDuration(0)).toBe("0s");
    expect(formatDuration(90)).toBe("1m 30s");
    expect(formatDuration(3 * 86400 + 4 * 3600 + 12 * 60)).toBe("3d 4h 12m");
    expect(formatDuration(null)).toBe("—");
  });
});

describe("formatRelative", () => {
  it("describes recent times", () => {
    expect(formatRelative(new Date(Date.now() - 10_000).toISOString())).toBe("just now");
    expect(formatRelative(new Date(Date.now() - 5 * 60_000).toISOString())).toBe("5m ago");
    expect(formatRelative(new Date(Date.now() - 3 * 3600_000).toISOString())).toBe("3h ago");
  });

  it("falls back for missing input", () => {
    expect(formatRelative(null)).toBe("—");
    expect(formatRelative("not a date")).toBe("—");
  });
});