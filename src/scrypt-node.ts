import { scrypt as nodeScrypt } from "node:crypto";

export function scrypt(
	password: string,
	salt: string,
	opts: { N: number; r: number; p: number; dkLen: number; maxmem?: number },
): Promise<Uint8Array> {
	return new Promise((resolve, reject) => {
		nodeScrypt(
			password,
			salt,
			opts.dkLen,
			{
				N: opts.N,
				r: opts.r,
				p: opts.p,
				maxmem: opts.maxmem ?? 128 * opts.N * opts.r * 2,
			},
			(err, key) => {
				if (err) reject(err);
				else resolve(new Uint8Array(key));
			},
		);
	});
}
