export class Names {
	reserved: string[] = [];
	values: string[] = [];
	globals: string[] = [];
	functions: string[] = [];
	signatures: string[] = [];
	constants: string[] = [];
	params: string[] = [];
	locals: string[] = [];
}

export function suffixed(name: string, taken: string[]): string {
	let unique = name;
	let suffix = 0;
	while (taken.includes(unique)) {
		suffix += 1;
		unique = name + "_" + String(suffix);
	}
	return unique;
}

export function fieldNames(reserved: string[], names: string[]): string[] {
	let spelled: string[] = [];
	for (const name of names) {
		let unique = name;
		let suffix = 0;
		while (reserved.includes(unique) || spelled.includes(unique) ||
			unique != name && names.includes(unique)) {
			suffix += 1;
			unique = name + "_" + String(suffix);
		}
		spelled.push(unique);
	}
	return spelled;
}

function taken(n: Names, name: string, parameterTypes: string, local: boolean): boolean {
	if (n.reserved.includes(name) || n.values.includes(name) || n.globals.includes(name)) {
		return true;
	}
	if (parameterTypes != "") { return n.signatures.includes(name + parameterTypes); }
	if (n.functions.includes(name) || n.constants.includes(name)) { return true; }
	return local && (n.params.includes(name) || n.locals.includes(name));
}

function free(n: Names, name: string, parameterTypes: string, local: boolean): string {
	let unique = name;
	let suffix = 0;
	while (taken(n, unique, parameterTypes, local)) {
		suffix += 1;
		unique = name + "_" + String(suffix);
	}
	return unique;
}

export function nameStruct(n: Names, name: string): string {
	const spelled = free(n, name, "", false);
	n.values.push(spelled);
	return spelled;
}

export function nameConstant(n: Names, name: string): string {
	const spelled = free(n, name, "", false);
	n.constants.push(spelled);
	return spelled;
}

export function nameFunction(n: Names, name: string, parameterTypes: string): string {
	const spelled = free(n, name, parameterTypes, false);
	n.functions.push(spelled);
	n.signatures.push(spelled + parameterTypes);
	n.params = [];
	n.locals = [];
	return spelled;
}

export function nameParam(n: Names, name: string): string {
	const spelled = free(n, name, "", true);
	n.params.push(spelled);
	return spelled;
}

export function nameLocal(n: Names, name: string): string {
	const spelled = free(n, name, "", true);
	n.locals.push(spelled);
	return spelled;
}
