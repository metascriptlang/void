import { exit } from "std/process";

@noinline export function stop(message: string): never {
	console.error("gpu door: " + message);
	exit(1);
}
