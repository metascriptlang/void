// VoidView — a plain UIKit view backed by a CAMetalLayer that the Void engine
// renders into. Reusable as-is: standalone UIKit hosts it directly, and the
// React-Native VoidViewManager returns one as its managed view (legacy bridge).
#import <UIKit/UIKit.h>

@interface VoidView : UIView
@end
