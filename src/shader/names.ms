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

function taken(names: Names, name: string, parameterTypes: string, local: boolean): boolean {
	if (names.reserved.includes(name) || names.values.includes(name) ||
		names.globals.includes(name)) {
		return true;
	}
	if (parameterTypes != "") { return names.signatures.includes(name + parameterTypes); }
	if (names.functions.includes(name) || names.constants.includes(name)) { return true; }
	return local && (names.params.includes(name) || names.locals.includes(name));
}

function free(names: Names, name: string, parameterTypes: string, local: boolean): string {
	let unique = name;
	let suffix = 0;
	while (taken(names, unique, parameterTypes, local)) {
		suffix += 1;
		unique = name + "_" + String(suffix);
	}
	return unique;
}

export function nameStruct(names: Names, name: string): string {
	const spelled = free(names, name, "", false);
	names.values.push(spelled);
	return spelled;
}

export function nameConstant(names: Names, name: string): string {
	const spelled = free(names, name, "", false);
	names.constants.push(spelled);
	return spelled;
}

export function nameFunction(names: Names, name: string, parameterTypes: string): string {
	const spelled = free(names, name, parameterTypes, false);
	names.functions.push(spelled);
	names.signatures.push(spelled + parameterTypes);
	names.params = [];
	names.locals = [];
	return spelled;
}

export function nameParam(names: Names, name: string): string {
	const spelled = free(names, name, "", true);
	names.params.push(spelled);
	return spelled;
}

export function nameLocal(names: Names, name: string): string {
	const spelled = free(names, name, "", true);
	names.locals.push(spelled);
	return spelled;
}
