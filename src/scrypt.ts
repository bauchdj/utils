import { scryptAsync } from "@noble/hashes/scrypt";

export async function scrypt(
	password: string,
	salt: string,
	opts: { N: number; r: number; p: number; dkLen: number; maxmem?: number },
): Promise<Uint8Array> {
	return scryptAsync(password, salt, {
		N: opts.N,
		r: opts.r,
		p: opts.p,
		dkLen: opts.dkLen,
		maxmem: opts.maxmem ?? 128 * opts.N * opts.r * 2,
	});
}
