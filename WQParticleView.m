#import "WQParticleView.h"

NSString * const WQParticleStyleNameKey = @"WQParticleStyleName";
NSString * const WQAppearanceModeKey = @"WQAppearanceMode";

NSArray<NSString *> *WQParticleStyleNames(void) { return @[@"constellation", @"embers", @"snow", @"orbit"]; }
NSString *WQParticleStyleName(void) {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:WQParticleStyleNameKey];
    return [WQParticleStyleNames() containsObject:value] ? value : @"constellation";
}
void WQSetParticleStyleName(NSString *name) {
    if (![WQParticleStyleNames() containsObject:name]) name = @"constellation";
    [NSUserDefaults.standardUserDefaults setObject:name forKey:WQParticleStyleNameKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WQParticleStyleDidChange" object:name];
}
NSString *WQAppearanceModeName(void) {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:WQAppearanceModeKey];
    return [@[ @"dark", @"light", @"auto" ] containsObject:value] ? value : @"dark";
}
void WQSetAppearanceModeName(NSString *name) {
    if (![@[ @"dark", @"light", @"auto" ] containsObject:name]) name = @"dark";
    [NSUserDefaults.standardUserDefaults setObject:name forKey:WQAppearanceModeKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WQAppearanceDidChange" object:name];
}

@interface WQParticleView ()
@property(nonatomic) NSMutableArray<NSValue *> *points;
@property(nonatomic) CADisplayLink *displayLink;
@property(nonatomic) CGFloat phase;
@end
@implementation WQParticleView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.points = [NSMutableArray array];
        for (NSUInteger i = 0; i < 42; i++) [self.points addObject:[NSValue valueWithCGPoint:CGPointMake((CGFloat)arc4random_uniform(1000)/1000.0, (CGFloat)arc4random_uniform(1000)/1000.0)]];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStyle) name:@"WQParticleStyleDidChange" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStyle) name:@"WQAppearanceDidChange" object:nil];
    }
    return self;
}
- (void)dealloc { [self.displayLink invalidate]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)refreshStyle { [self setNeedsDisplay]; }
- (void)tick:(CADisplayLink *)link { self.phase += link.duration * 0.35; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    NSString *style = WQParticleStyleName();
    UIColor *dot = [WQAppearanceModeName() isEqualToString:@"light"] ? [UIColor blackColor] : [UIColor whiteColor];
    NSUInteger index = 0;
    for (NSValue *value in self.points) {
        CGPoint p = value.CGPointValue;
        CGFloat x = p.x * rect.size.width;
        CGFloat y = fmod(p.y * rect.size.height + self.phase * (18 + index % 5), rect.size.height);
        CGFloat radius = [style isEqualToString:@"embers"] ? 2.2 : ([style isEqualToString:@"snow"] ? 1.5 : 1.8);
        CGFloat alpha = [style isEqualToString:@"orbit"] ? 0.28 : 0.16;
        CGContextSetFillColorWithColor(ctx, [dot colorWithAlphaComponent:alpha].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x-radius, y-radius, radius*2, radius*2));
        index++;
    }
    if ([style isEqualToString:@"constellation"]) {
        CGContextSetStrokeColorWithColor(ctx, [dot colorWithAlphaComponent:0.06].CGColor);
        CGContextSetLineWidth(ctx, 0.5);
        for (NSUInteger i = 1; i < self.points.count; i += 3) {
            CGPoint a = self.points[i-1].CGPointValue, b = self.points[i].CGPointValue;
            CGContextMoveToPoint(ctx, a.x * rect.size.width, a.y * rect.size.height);
            CGContextAddLineToPoint(ctx, b.x * rect.size.width, b.y * rect.size.height);
            CGContextStrokePath(ctx);
        }
    }
}
@end
