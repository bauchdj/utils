import { describe, it, expect } from "vitest";
import { scrypt } from "./scrypt-node";

describe("scrypt", () => {
	const password = "password";
	const salt = "salt";
	const opts = { N: 16384, r: 8, p: 1, dkLen: 64 };

	it("returns a Uint8Array of the correct length", async () => {
		const result = await scrypt(password, salt, opts);
		expect(result).toBeInstanceOf(Uint8Array);
		expect(result.length).toBe(opts.dkLen);
	});

	it("produces deterministic output", async () => {
		const result1 = await scrypt(password, salt, opts);
		const result2 = await scrypt(password, salt, opts);
		expect(result1).toEqual(result2);
	});

	it("produces different output for different passwords", async () => {
		const result1 = await scrypt("password1", salt, opts);
		const result2 = await scrypt("password2", salt, opts);
		expect(result1).not.toEqual(result2);
	});

	it("produces different output for different salts", async () => {
		const result1 = await scrypt(password, "salt1", opts);
		const result2 = await scrypt(password, "salt2", opts);
		expect(result1).not.toEqual(result2);
	});

	it("matches known scrypt vector", async () => {
		const result = await scrypt("password", "salt", {
			N: 1024,
			r: 8,
			p: 16,
			dkLen: 64,
		});
		const hex = Array.from(result)
			.map((b) => b.toString(16).padStart(2, "0"))
			.join("");
		expect(hex).toBe(
			"1effd93afcf2b28964026631bf4362b0e5ed83cbd5f326b72eb687bfbc7ac567" +
				"56f8d92337963b22c53ecab5e8de24f3b24053bfb5341c28f162aca6b0898a6e",
		);
	});
});
