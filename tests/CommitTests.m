#import <Cocoa/Cocoa.h>
#import "AvroKeyboardController.h"

// Link-only stand-ins for services never invoked by these commit-path tests.
@interface AvroParser : NSObject @end
@implementation AvroParser @end
@interface Suggestion : NSObject @end
@implementation Suggestion @end
@interface CacheManager : NSObject @end
@implementation CacheManager @end
@interface AutoCorrect : NSObject @end
@implementation AutoCorrect @end

static NSAttributedString *panelSelection;
@interface Candidates : NSObject
+ (id)sharedInstance;
- (NSAttributedString *)selectedCandidateString;
@end
@implementation Candidates
+ (id)sharedInstance { static id panel; if (!panel) panel = [self new]; return panel; }
- (NSAttributedString *)selectedCandidateString { return panelSelection; }
@end

@interface TestClient : NSObject { @public NSMutableArray *insertions; }
@end
@implementation TestClient
- (id)init { if ((self = [super init])) insertions = [NSMutableArray new]; return self; }
- (void)insertText:(id)text replacementRange:(NSRange)range {
    NSCAssert(text != nil, @"must never insert nil");
    NSCAssert(range.location == NSNotFound && range.length == 0, @"replacement range changed");
    [insertions addObject:[text isKindOfClass:[NSAttributedString class]] ? [text string] : text];
}
@end

@interface TestController : AvroKeyboardController { @public TestClient *activeClient; }
@end
@implementation TestController
- (id)client { return activeClient; }
- (void)updateCandidatesPanel { /* No UI in isolated regression executable. */ }
@end

static TestController *controller(NSArray *choices, NSInteger remembered) {
    // Deliberately omit IMK server initialization; only exercise the real commit methods.
    TestController *c = [TestController alloc];
    c->activeClient = [TestClient new];
    [c setValue:[NSMutableString stringWithString:@"ami"] forKey:@"composedBuffer"];
    [c setValue:[NSMutableArray arrayWithArray:choices] forKey:@"currentCandidates"];
    [c setValue:@(remembered) forKey:@"prevSelected"];
    return c;
}
static void expect(TestController *c, NSArray *values, const char *name) {
    NSCAssert([c->activeClient->insertions isEqualToArray:values], @"%s unexpected insertion %@", name, c->activeClient->insertions);
    if (values.count) {
        NSCAssert([[c valueForKey:@"composedBuffer"] length] == 0, @"composition not cleared");
        NSCAssert([[c valueForKey:@"currentCandidates"] count] == 0, @"candidates not cleared");
    }
    printf("PASS %s\n", name);
}
int main(void) {
 @autoreleasepool {
  @try {
    NSArray *choices = @[@"আমি", @"অমি"];
    panelSelection = nil;
    TestController *c = controller(choices, -1);
    NSCAssert(![c inputText:@" " client:c->activeClient], @"Space must pass through after commit");
    expect(c, @[@"আমি"], "Space falls back to first candidate");
    c = controller(choices, 1); [c inputText:@" " client:c->activeClient];
    expect(c, @[@"অমি"], "missing panel selection honors remembered candidate");
    c = controller(choices, 99); [c inputText:@" " client:c->activeClient];
    expect(c, @[@"আমি"], "invalid remembered index safely uses first candidate");
    panelSelection = [[NSAttributedString alloc] initWithString:@"অমি"];
    c = controller(choices, 0); [c inputText:@" " client:c->activeClient];
    expect(c, @[@"অমি"], "explicit panel choice takes priority");
    panelSelection = nil;
    c = controller(choices, -1); [c commitText:@"\n"];
    expect(c, @[@"আমি", @"\n"], "Return commits candidate then newline");
    c = controller(choices, -1); [c commitText:@"\t"];
    expect(c, @[@"আমি", @"\t"], "Tab commits candidate then tab");
    c = controller(choices, -1); TestClient *oldClient = c->activeClient; c->activeClient = [TestClient new];
    [c candidateSelected:[[NSAttributedString alloc] initWithString:@"আমি"]];
    NSCAssert(oldClient->insertions.count == 0, @"old client received text");
    expect(c, @[@"আমি"], "clicked candidate uses current client after client change");
    c = controller(@[], -1); NSCAssert(![c inputText:@" " client:c->activeClient], @"empty Space swallowed");
    expect(c, @[], "empty candidate list inserts nothing and passes Space through");
  } @catch (NSException *exception) {
    fprintf(stderr, "FAIL %s\n", [[exception reason] UTF8String]);
    return 1;
  }
 }
 return 0;
}
