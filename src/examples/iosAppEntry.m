#import <Foundation/Foundation.h>

extern void MsMain(void);
extern int cmdCount;
extern char **cmdLine;
extern char **gEnv;
extern int msProgramResult;

int main(int argc, char **argv, char **env) {
	cmdCount = argc;
	cmdLine = argv;
	gEnv = env;
	@autoreleasepool {
		MsMain();
	}
	return msProgramResult;
}
