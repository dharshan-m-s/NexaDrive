import { describe, expect, it } from "vitest";
import { csrfHeaderFromCookie } from "./api";

describe("csrfHeaderFromCookie", () => {
  it("finds the csrf cookie among others", () => {
    expect(csrfHeaderFromCookie("session=abc; nexa_console_csrf=token123; x=y")).toBe(
      "token123",
    );
  });

  it("returns null when absent or empty", () => {
    expect(csrfHeaderFromCookie("session=abc")).toBeNull();
    expect(csrfHeaderFromCookie("nexa_console_csrf=")).toBeNull();
    expect(csrfHeaderFromCookie("")).toBeNull();
  });

  it("preserves values containing equals signs", () => {
    expect(csrfHeaderFromCookie("nexa_console_csrf=ab=cd=")).toBe("ab=cd=");
  });

  it("does not match a lookalike name", () => {
    expect(csrfHeaderFromCookie("my_nexa_console_csrf=token")).toBeNull();
  });
});