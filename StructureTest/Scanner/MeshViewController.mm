/*
  This file is part of the Structure SDK.
  Copyright © 2019 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "MeshViewController.h"
#import "MeshRenderer.h"
#import "ViewpointController.h"
#import "CustomUIKitStyles.h"
#import "DisclaimerActivityItemSource.h"

#import <ImageIO/ImageIO.h>

#include <vector>
#include <cmath>

// Local Helper Functions
static void saveJpegFromRGBABuffer(const char* filename, unsigned char* src_buffer, int width, int height)
{
    FILE* file = fopen(filename, "w");
    if (!file)
        return;

    CGColorSpaceRef colorSpace;
    CGImageAlphaInfo alphaInfo;
    CGContextRef context;

    colorSpace = CGColorSpaceCreateDeviceRGB();
    alphaInfo = kCGImageAlphaNoneSkipLast;
    context = CGBitmapContextCreate(src_buffer, width, height, 8, width * 4, colorSpace, alphaInfo);
    CGImageRef rgbImage = CGBitmapContextCreateImage(context);

    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    CFMutableDataRef jpgData = CFDataCreateMutable(NULL, 0);

    CGImageDestinationRef imageDest = CGImageDestinationCreateWithData(jpgData, CFSTR("public.jpeg"), 1, NULL);
    CFDictionaryRef options = CFDictionaryCreate(
        kCFAllocatorDefault, // Our empty IOSurface properties dictionary
        NULL,
        NULL,
        0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CGImageDestinationAddImage(imageDest, rgbImage, (CFDictionaryRef)options);
    CGImageDestinationFinalize(imageDest);
    CFRelease(imageDest);
    CFRelease(options);
    CGImageRelease(rgbImage);

    fwrite(CFDataGetBytePtr(jpgData), 1, CFDataGetLength(jpgData), file);
    fclose(file);
    CFRelease(jpgData);
}

@interface MeshViewController ()
{
    STMesh* _mesh;
    CADisplayLink* _displayLink;
    MeshRenderer* _renderer;
    ViewpointController* _viewpointController;
    GLfloat _glViewport[4];

    GLKMatrix4 _modelViewMatrixBeforeUserInteractions;
    GLKMatrix4 _projectionMatrixBeforeUserInteractions;
}

@property UIActivityViewController* shareViewController;

@end

@implementation MeshViewController

@synthesize mesh = _mesh;

+ (instancetype)viewController
{
    MeshViewController* vc = [[MeshViewController alloc] initWithNibName:@"MeshView" bundle:nil];
    return vc;
}

- (id)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
    UIBarButtonItem* backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(dismissView)];
    self.navigationItem.leftBarButtonItem = backButton;

    UIBarButtonItem* shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                 target:self
                                                                                 action:@selector(shareMesh:)];
    self.navigationItem.rightBarButtonItem = shareButton;

    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        // Custom initialization
        self.title = @"Structure Sensor Scanner";
    }

    return self;
}

- (void)setupGestureRecognizer
{
    UIPinchGestureRecognizer* pinchScaleGesture =
        [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchScaleGesture:)];
    [pinchScaleGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchScaleGesture];

    // We'll use one finger pan for rotation.
    UIPanGestureRecognizer* oneFingerPanGesture =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(oneFingerPanGesture:)];
    [oneFingerPanGesture setDelegate:self];
    [oneFingerPanGesture setMaximumNumberOfTouches:1];
    [self.view addGestureRecognizer:oneFingerPanGesture];

    // We'll use two fingers pan for in-plane translation.
    UIPanGestureRecognizer* twoFingersPanGesture =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(twoFingersPanGesture:)];
    [twoFingersPanGesture setDelegate:self];
    [twoFingersPanGesture setMaximumNumberOfTouches:2];
    [twoFingersPanGesture setMinimumNumberOfTouches:2];
    [self.view addGestureRecognizer:twoFingersPanGesture];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.meshViewerMessageLabel.alpha = 0.0;
    self.meshViewerMessageLabel.hidden = true;

    [self.meshViewerMessageLabel applyCustomStyleWithBackgroundColor:blackLabelColorWithLightAlpha];

    _renderer = new MeshRenderer();
    _viewpointController = new ViewpointController(self.view.frame.size.width, self.view.frame.size.height);

    UIFont* font = [UIFont boldSystemFontOfSize:14.0f];
    NSDictionary* attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];

    [self.displayControl setTitleTextAttributes:attributes forState:UIControlStateNormal];

    [self setupGestureRecognizer];
}

- (void)setLabel:(UILabel*)label enabled:(BOOL)enabled
{

    UIColor* whiteLightAlpha = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.5];

    if (enabled)
        [label setTextColor:[UIColor whiteColor]];
    else
        [label setTextColor:whiteLightAlpha];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (_displayLink)
    {
        [_displayLink invalidate];
        _displayLink = nil;
    }

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    _viewpointController->reset();

    if (!self.colorEnabled)
        [self.displayControl removeSegmentAtIndex:2 animated:NO];

    self.displayControl.selectedSegmentIndex = 1;
    _renderer->setRenderingMode(MeshRenderer::RenderingModeLightedGray);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)setupGL:(EAGLContext*)context
{
    [(EAGLView*)self.view setContext:context];
    [EAGLContext setCurrentContext:context];

    _renderer->initializeGL();

    [(EAGLView*)self.view setFramebuffer];
    CGSize framebufferSize = [(EAGLView*)self.view getFramebufferSize];

    float imageAspectRatio = 1.0f;

    // The iPad's diplay conveniently has a 4:3 aspect ratio just like our video feed.
    // Some iOS devices need to render to only a portion of the screen so that we don't distort
    // our RGB image. Alternatively, you could enlarge the viewport (losing visual information),
    // but fill the whole screen.
    if (std::abs(framebufferSize.width / framebufferSize.height - 640.0f / 480.0f) > 1e-3)
        imageAspectRatio = 480.f / 640.0f;

    _glViewport[0] = (framebufferSize.width - framebufferSize.width * imageAspectRatio) / 2;
    _glViewport[1] = 0;
    _glViewport[2] = framebufferSize.width * imageAspectRatio;
    _glViewport[3] = framebufferSize.height;
}

- (void)dismissView
{
    if ([self.delegate respondsToSelector:@selector(meshViewWillDismiss)])
        [self.delegate meshViewWillDismiss];

    // Make sure we clear the data we don't need.
    _renderer->releaseGLBuffers();
    _renderer->releaseGLTextures();

    [_displayLink invalidate];
    _displayLink = nil;

    self.mesh = nil;

    [(EAGLView*)self.view setContext:nil];

    [self dismissViewControllerAnimated:YES completion:^{
        if ([self.delegate respondsToSelector:@selector(meshViewDidDismiss)])
            [self.delegate meshViewDidDismiss];
    }];
}

#pragma mark - MeshViewer setup when loading the mesh

- (void)setCameraProjectionMatrix:(GLKMatrix4)projection
{
    _viewpointController->setCameraProjection(projection);
    _projectionMatrixBeforeUserInteractions = projection;
}

- (void)resetMeshCenter:(GLKVector3)center
{
    _viewpointController->reset();
    _viewpointController->setMeshCenter(center);
    _modelViewMatrixBeforeUserInteractions = _viewpointController->currentGLModelViewMatrix();
}

- (void)setMesh:(STMesh*)meshRef
{
    _mesh = meshRef;

    if (meshRef)
    {
        _renderer->uploadMesh(meshRef);

        [self trySwitchToColorRenderingMode];

        self.needsDisplay = TRUE;
    }
}

#pragma mark - Mesh file share

- (void)prepareScreenShot:(NSString*)screenshotPath
{
    const int width = 320;
    const int height = 240;

    GLint currentFrameBuffer;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFrameBuffer);

    // Create temp texture, framebuffer, renderbuffer
    glViewport(0, 0, width, height);

    GLuint outputTexture;
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &outputTexture);
    glBindTexture(GL_TEXTURE_2D, outputTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);

    GLuint colorFrameBuffer, depthRenderBuffer;
    glGenFramebuffers(1, &colorFrameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, colorFrameBuffer);
    glGenRenderbuffers(1, &depthRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderBuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, outputTexture, 0);

    // Keep the current render mode
    MeshRenderer::RenderingMode previousRenderingMode = _renderer->getRenderingMode();

    STMesh* meshToRender = _mesh;

    // Screenshot rendering mode, always use colors if possible.
    if ([meshToRender hasPerVertexUVTextureCoords] && [meshToRender meshYCbCrTexture])
    {
        _renderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
    }
    else if ([meshToRender hasPerVertexColors])
    {
        _renderer->setRenderingMode(MeshRenderer::RenderingModePerVertexColor);
    }
    else // meshToRender can be nil if there is no available color mesh.
    {
        _renderer->setRenderingMode(MeshRenderer::RenderingModeLightedGray);
    }

    // Render from the initial viewpoint for the screenshot.
    _renderer->clear();
    _renderer->render(_projectionMatrixBeforeUserInteractions, _modelViewMatrixBeforeUserInteractions);

    // Back to current render mode
    _renderer->setRenderingMode(previousRenderingMode);

    struct RgbaPixel
    {
        uint8_t rgba[4];
    };
    std::vector<RgbaPixel> screenShotRgbaBuffer(width * height);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, screenShotRgbaBuffer.data());

    // We need to flip the axis, because OpenGL reads out the buffer from the bottom.
    std::vector<RgbaPixel> rowBuffer(width);
    for (int h = 0; h < height / 2; ++h)
    {
        RgbaPixel* screenShotDataTopRow = screenShotRgbaBuffer.data() + h * width;
        RgbaPixel* screenShotDataBottomRow = screenShotRgbaBuffer.data() + (height - h - 1) * width;

        // Swap the top and bottom rows, using rowBuffer as a temporary placeholder.
        memcpy(rowBuffer.data(), screenShotDataTopRow, width * sizeof(RgbaPixel));
        memcpy(screenShotDataTopRow, screenShotDataBottomRow, width * sizeof(RgbaPixel));
        memcpy(screenShotDataBottomRow, rowBuffer.data(), width * sizeof(RgbaPixel));
    }

    saveJpegFromRGBABuffer(
        [screenshotPath UTF8String],
        reinterpret_cast<uint8_t*>(screenShotRgbaBuffer.data()),
        width,
        height);

    // Back to the original frame buffer
    glBindFramebuffer(GL_FRAMEBUFFER, currentFrameBuffer);
    glViewport(_glViewport[0], _glViewport[1], _glViewport[2], _glViewport[3]);

    // Free the data
    glDeleteTextures(1, &outputTexture);
    glDeleteFramebuffers(1, &colorFrameBuffer);
    glDeleteRenderbuffers(1, &depthRenderBuffer);
}

- (NSNumber*)getMeshExportFormat
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    switch ([defaults integerForKey:@"meshExportFormat"])
    {
        case 0: return @(STMeshWriteOptionFileFormatObjFileZip);

        case 1: return @(STMeshWriteOptionFileFormatPlyFile);

        case 2: return @(STMeshWriteOptionFileFormatBinarySTLFile);
            
        default:
            return nil;
    }
}

- (void)shareMesh:(id)sender
{
    NSString* cacheDirectory =
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];

    // Prepare screenshot
    NSString* screenshotPath = [cacheDirectory stringByAppendingPathComponent:@"Preview.jpg"];

    // Take a screenshot and save it to disk.
    [self prepareScreenShot:screenshotPath];

    NSDictionary* exportExtensions = @{
        @(STMeshWriteOptionFileFormatObjFileZip): @"zip",
        @(STMeshWriteOptionFileFormatPlyFile): @"ply",
        @(STMeshWriteOptionFileFormatBinarySTLFile): @"stl"
    };

    NSNumber* meshExportFormat = [self getMeshExportFormat];

    // Request a zipped OBJ file, potentially with embedded MTL and texture.
    NSDictionary* options =
        @{kSTMeshWriteOptionFileFormatKey: meshExportFormat, kSTMeshWriteOptionUseXRightYUpConventionKey: @YES};

    NSString* zipFileName = [NSString stringWithFormat:@"Model.%@", exportExtensions[meshExportFormat]];
    NSString* zipPath = [cacheDirectory stringByAppendingPathComponent:zipFileName];
    NSError* error;
    BOOL success = [_mesh writeToFile:zipPath options:options error:&error];
    if (!success)
    {
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:@"Mesh cannot be exported"
                             message:[NSString stringWithFormat:@"Exporting failed: %@.", [error localizedDescription]]
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction* action){}];

        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];

        return;
    }

    UIImage* image = [[UIImage alloc] initWithContentsOfFile:screenshotPath];
    NSURL* meshFile = [NSURL fileURLWithPath:zipPath];

    // The order is important to appear in the mail template
    NSArray* activityItems = @[[DisclaimerActivityItemSource new], image, meshFile];

    self.shareViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                                                 applicationActivities:nil];
    self.shareViewController.excludedActivityTypes =
        @[UIActivityTypeAssignToContact, UIActivityTypePrint, UIActivityTypePostToWeibo];

    if (self.shareViewController.popoverPresentationController)
    {
        self.shareViewController.popoverPresentationController.sourceView = self.view;
        self.shareViewController.popoverPresentationController.barButtonItem = (UIBarButtonItem*)sender;
    }

    [self presentViewController:self.shareViewController animated:YES completion:nil];
}

#pragma mark - Rendering

- (void)draw
{
    [(EAGLView*)self.view setFramebuffer];

    glViewport(_glViewport[0], _glViewport[1], _glViewport[2], _glViewport[3]);

    bool viewpointChanged = _viewpointController->update();

    // If nothing changed, do not waste time and resources rendering.
    if (!_needsDisplay && !viewpointChanged)
        return;

    GLKMatrix4 currentModelView = _viewpointController->currentGLModelViewMatrix();
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();

    _renderer->clear();
    _renderer->render(currentProjection, currentModelView);

    _needsDisplay = FALSE;

    [(EAGLView*)self.view presentFramebuffer];
}

#pragma mark - Touch & Gesture control

- (void)pinchScaleGesture:(UIPinchGestureRecognizer*)gestureRecognizer
{
    // Forward to the ViewpointController.
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onPinchGestureBegan([gestureRecognizer scale]);
    else if ([gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onPinchGestureChanged([gestureRecognizer scale]);
}

- (void)oneFingerPanGesture:(UIPanGestureRecognizer*)gestureRecognizer
{
    CGPoint touchPos = [gestureRecognizer locationInView:self.view];
    CGPoint touchVel = [gestureRecognizer velocityInView:self.view];
    GLKVector2 touchPosVec = GLKVector2Make(touchPos.x, touchPos.y);
    GLKVector2 touchVelVec = GLKVector2Make(touchVel.x, touchVel.y);

    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onOneFingerPanBegan(touchPosVec);
    else if ([gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onOneFingerPanChanged(touchPosVec);
    else if ([gestureRecognizer state] == UIGestureRecognizerStateEnded)
        _viewpointController->onOneFingerPanEnded(touchVelVec);
}

- (void)twoFingersPanGesture:(UIPanGestureRecognizer*)gestureRecognizer
{
    if ([gestureRecognizer numberOfTouches] != 2)
        return;

    CGPoint touchPos = [gestureRecognizer locationInView:self.view];
    CGPoint touchVel = [gestureRecognizer velocityInView:self.view];
    GLKVector2 touchPosVec = GLKVector2Make(touchPos.x, touchPos.y);
    GLKVector2 touchVelVec = GLKVector2Make(touchVel.x, touchVel.y);

    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onTwoFingersPanBegan(touchPosVec);
    else if ([gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onTwoFingersPanChanged(touchPosVec);
    else if ([gestureRecognizer state] == UIGestureRecognizerStateEnded)
        _viewpointController->onTwoFingersPanEnded(touchVelVec);
}

- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
    _viewpointController->onTouchBegan();
}

#pragma mark - UI Control

- (void)trySwitchToColorRenderingMode
{
    // Choose the best available color render mode, falling back to LightedGray

    // This method may be called when colorize operations complete, and will
    // switch the render mode to color, as long as the user has not changed
    // the selector.

    if (self.displayControl.selectedSegmentIndex == 2)
    {
        if ([_mesh hasPerVertexUVTextureCoords])
            _renderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
        else if ([_mesh hasPerVertexColors])
            _renderer->setRenderingMode(MeshRenderer::RenderingModePerVertexColor);
        else
            _renderer->setRenderingMode(MeshRenderer::RenderingModeLightedGray);
    }
}

- (IBAction)openDeveloperPortal:(id)sender
{
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://structure.io/developers"] options:@{} completionHandler:nil];
}

- (IBAction)displayControlChanged:(id)sender
{

    switch (self.displayControl.selectedSegmentIndex)
    {
        case 0: // x-ray
        {
            _renderer->setRenderingMode(MeshRenderer::RenderingModeXRay);
        }
        break;
        case 1: // lighted-gray
        {
            _renderer->setRenderingMode(MeshRenderer::RenderingModeLightedGray);
        }
        break;
        case 2: // color
        {
            [self trySwitchToColorRenderingMode];

            bool meshIsColorized = [_mesh hasPerVertexColors] || [_mesh hasPerVertexUVTextureCoords];

            if (!meshIsColorized)
                [self colorizeMesh];
        }
        break;
        default: break;
    }

    self.needsDisplay = TRUE;
}

- (void)colorizeMesh
{
    [self.delegate meshViewDidRequestColorizing:_mesh previewCompletionHandler:^{} enhancedCompletionHandler:^{
        // Hide progress bar.
        [self hideMeshViewerMessage];
    }];
}

- (void)hideMeshViewerMessage
{
    [UIView animateWithDuration:0.5f animations:^{ self.meshViewerMessageLabel.alpha = 0.0f; }
        completion:^(BOOL finished) { [self.meshViewerMessageLabel setHidden:YES]; }];
}

- (void)showMeshViewerMessage:(NSString*)msg
{
    [self.meshViewerMessageLabel setText:msg];

    if (self.meshViewerMessageLabel.hidden == YES)
    {
        [self.meshViewerMessageLabel setHidden:NO];

        self.meshViewerMessageLabel.alpha = 0.0f;
        [UIView animateWithDuration:0.5f animations:^{ self.meshViewerMessageLabel.alpha = 1.0f; }];
    }
}

@end
