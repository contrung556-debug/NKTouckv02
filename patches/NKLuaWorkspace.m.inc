// NKTouch Lua Workspace UX layer (V7.4)
// Appended to SettingsPageViewController.m by prepare-v074.sh so the pinned
// upstream Xcode project does not need a project.pbxproj mutation.

#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

static NSString * const NKLuaScriptsPath = @"/var/mobile/Library/NKTouch/scripts";
static NSString * const NKLuaEditorTool = @"/var/jb/usr/bin/nkeditor";

static NSString *NKLuaRunTool(NSArray<NSString *> *arguments, int *exitCode) {
    int outputPipe[2] = {-1, -1};
    if (pipe(outputPipe) != 0) {
        if (exitCode) *exitCode = 126;
        return @"Unable to create command pipe.";
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outputPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outputPipe[1]);

    NSUInteger argc = arguments.count + 2;
    char **argv = calloc(argc, sizeof(char *));
    argv[0] = strdup(NKLuaEditorTool.UTF8String);
    for (NSUInteger i = 0; i < arguments.count; i++) {
        argv[i + 1] = strdup(arguments[i].UTF8String);
    }
    argv[arguments.count + 1] = NULL;

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, NKLuaEditorTool.UTF8String, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(outputPipe[1]);

    for (NSUInteger i = 0; i < arguments.count + 1; i++) free(argv[i]);
    free(argv);

    if (spawnResult != 0) {
        close(outputPipe[0]);
        if (exitCode) *exitCode = spawnResult;
        return [NSString stringWithFormat:@"Unable to launch nkeditor (%d).", spawnResult];
    }

    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    ssize_t amount = 0;
    while ((amount = read(outputPipe[0], buffer, sizeof(buffer))) > 0) {
        [data appendBytes:buffer length:(NSUInteger)amount];
        if (data.length > (512 * 1024)) break;
    }
    close(outputPipe[0]);

    int status = 0;
    waitpid(pid, &status, 0);
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 125;
    if (exitCode) *exitCode = code;

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length) text = code == 0 ? @"OK" : [NSString stringWithFormat:@"Command failed (%d).", code];
    return text;
}

@interface NKLuaWorkspaceViewController : UIViewController <UITextViewDelegate>
@property(nonatomic,strong) UIButton *scriptButton;
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UITextView *codeView;
@property(nonatomic,strong) UITextView *consoleView;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,copy) NSString *scriptName;
@property(nonatomic,assign) BOOL dirty;
@end

@implementation NKLuaWorkspaceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Lua Workspace";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:NKLuaScriptsPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&dirError];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"New"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(newScript)];

    self.scriptButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scriptButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.scriptButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.scriptButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.scriptButton addTarget:self action:@selector(chooseScript) forControlEvents:UIControlEventTouchUpInside];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.stateLabel.textAlignment = NSTextAlignmentRight;
    self.stateLabel.text = @"Ready";
    self.stateLabel.textColor = UIColor.secondaryLabelColor;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;

    UIView *fileBar = [[UIView alloc] init];
    fileBar.translatesAutoresizingMaskIntoConstraints = NO;
    fileBar.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    fileBar.layer.cornerRadius = 12;
    [fileBar addSubview:self.scriptButton];
    [fileBar addSubview:self.stateLabel];
    [fileBar addSubview:self.spinner];

    UILabel *editorTitle = [[UILabel alloc] init];
    editorTitle.translatesAutoresizingMaskIntoConstraints = NO;
    editorTitle.text = @"CODE";
    editorTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    editorTitle.textColor = UIColor.secondaryLabelColor;

    self.codeView = [[UITextView alloc] init];
    self.codeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.codeView.delegate = self;
    self.codeView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.codeView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.codeView.textColor = UIColor.labelColor;
    self.codeView.layer.cornerRadius = 12;
    self.codeView.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    self.codeView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.codeView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.codeView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.codeView.smartDashesType = UITextSmartDashesTypeNo;
    self.codeView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

    UIButton *(^makeButton)(NSString *, SEL) = ^UIButton *(NSString *title, SEL selector) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setTitle:title forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        button.layer.cornerRadius = 10;
        [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
        return button;
    };

    UIButton *save = makeButton(@"Save", @selector(saveTapped));
    UIButton *check = makeButton(@"Check", @selector(checkTapped));
    UIButton *run = makeButton(@"▶ Run", @selector(runTapped));
    UIButton *stop = makeButton(@"■ Stop", @selector(stopTapped));
    UIButton *logs = makeButton(@"Logs", @selector(logsTapped));

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[save, check, run, stop, logs]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 7;
    actions.distribution = UIStackViewDistributionFillEqually;

    UILabel *consoleTitle = [[UILabel alloc] init];
    consoleTitle.translatesAutoresizingMaskIntoConstraints = NO;
    consoleTitle.text = @"CONSOLE";
    consoleTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    consoleTitle.textColor = UIColor.secondaryLabelColor;

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [clear setTitle:@"Clear" forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [clear addTarget:self action:@selector(clearConsole) forControlEvents:UIControlEventTouchUpInside];

    self.consoleView = [[UITextView alloc] init];
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleView.editable = NO;
    self.consoleView.selectable = YES;
    self.consoleView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.consoleView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.consoleView.textColor = UIColor.secondaryLabelColor;
    self.consoleView.layer.cornerRadius = 12;
    self.consoleView.textContainerInset = UIEdgeInsetsMake(10, 9, 10, 9);
    self.consoleView.text = @"Ready. Edit Lua, then Check or Run.";

    [self.view addSubview:fileBar];
    [self.view addSubview:editorTitle];
    [self.view addSubview:self.codeView];
    [self.view addSubview:actions];
    [self.view addSubview:consoleTitle];
    [self.view addSubview:clear];
    [self.view addSubview:self.consoleView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [fileBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [fileBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [fileBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [fileBar.heightAnchor constraintEqualToConstant:48],

        [self.scriptButton.leadingAnchor constraintEqualToAnchor:fileBar.leadingAnchor constant:12],
        [self.scriptButton.centerYAnchor constraintEqualToAnchor:fileBar.centerYAnchor],
        [self.scriptButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateLabel.leadingAnchor constant:-8],
        [self.spinner.trailingAnchor constraintEqualToAnchor:fileBar.trailingAnchor constant:-10],
        [self.spinner.centerYAnchor constraintEqualToAnchor:fileBar.centerYAnchor],
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:self.spinner.leadingAnchor constant:-6],
        [self.stateLabel.centerYAnchor constraintEqualToAnchor:fileBar.centerYAnchor],

        [editorTitle.topAnchor constraintEqualToAnchor:fileBar.bottomAnchor constant:10],
        [editorTitle.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],

        [self.codeView.topAnchor constraintEqualToAnchor:editorTitle.bottomAnchor constant:5],
        [self.codeView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.codeView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],

        [actions.topAnchor constraintEqualToAnchor:self.codeView.bottomAnchor constant:8],
        [actions.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [actions.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [actions.heightAnchor constraintEqualToConstant:42],

        [consoleTitle.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:10],
        [consoleTitle.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [clear.centerYAnchor constraintEqualToAnchor:consoleTitle.centerYAnchor],
        [clear.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        [self.consoleView.topAnchor constraintEqualToAnchor:consoleTitle.bottomAnchor constant:5],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [self.consoleView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8],

        [self.codeView.heightAnchor constraintGreaterThanOrEqualToConstant:190],
        [self.consoleView.heightAnchor constraintGreaterThanOrEqualToConstant:110],
        [self.codeView.heightAnchor constraintEqualToAnchor:self.consoleView.heightAnchor multiplier:1.7]
    ]];

    [self loadInitialScript];
}

- (NSArray<NSString *> *)scriptNames {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:NKLuaScriptsPath error:nil] ?: @[];
    NSPredicate *luaOnly = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        (void)bindings;
        return [name.pathExtension.lowercaseString isEqualToString:@"lua"] && ![name hasPrefix:@"."];
    }];
    return [[files filteredArrayUsingPredicate:luaOnly] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSString *)pathForScript:(NSString *)name {
    return [NKLuaScriptsPath stringByAppendingPathComponent:name];
}

- (NSString *)starterCode {
    return @"-- NKTouch Lua Workspace\n"
            @"local nk = require(\"nktouch_v7\")\n\n"
            @"-- Write automation below.\n"
            @"-- Example: assert(nk.tap(120, 450))\n";
}

- (NSString *)normalizedName:(NSString *)raw {
    NSString *name = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) return nil;
    if (![name.pathExtension.lowercaseString isEqualToString:@"lua"]) name = [name stringByAppendingPathExtension:@"lua"];
    if ([name containsString:@"/"] || [name containsString:@"\\"] || [name containsString:@".."] || [name hasPrefix:@"."]) return nil;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"] invertedSet];
    if ([name rangeOfCharacterFromSet:bad].location != NSNotFound) return nil;
    return name;
}

- (void)loadInitialScript {
    NSArray<NSString *> *scripts = [self scriptNames];
    NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey:@"NKLuaWorkspaceLastScript"];
    NSString *chosen = [scripts containsObject:last] ? last : scripts.firstObject;
    if (!chosen) {
        chosen = @"main.lua";
        [[self starterCode] writeToFile:[self pathForScript:chosen] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [self loadScript:chosen];
}

- (void)loadScript:(NSString *)name {
    if (self.dirty) [self saveCurrent:NO];
    NSString *text = [NSString stringWithContentsOfFile:[self pathForScript:name]
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (!text) return;
    self.scriptName = name;
    self.codeView.text = text;
    self.dirty = NO;
    [self.scriptButton setTitle:[NSString stringWithFormat:@"%@  ▾", name] forState:UIControlStateNormal];
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"NKLuaWorkspaceLastScript"];
    [self setState:@"Ready" color:UIColor.secondaryLabelColor];
}

- (void)setState:(NSString *)text color:(UIColor *)color {
    self.stateLabel.text = text;
    self.stateLabel.textColor = color;
}

- (void)textViewDidChange:(UITextView *)textView {
    if (textView != self.codeView) return;
    self.dirty = YES;
    [self setState:@"Unsaved" color:UIColor.systemOrangeColor];
}

- (BOOL)saveCurrent:(BOOL)showConsole {
    if (!self.scriptName.length) return NO;
    NSError *error = nil;
    BOOL ok = [self.codeView.text writeToFile:[self pathForScript:self.scriptName]
                                   atomically:YES
                                     encoding:NSUTF8StringEncoding
                                        error:&error];
    if (ok) {
        self.dirty = NO;
        [self setState:@"Saved" color:UIColor.systemGreenColor];
        if (showConsole) self.consoleView.text = [NSString stringWithFormat:@"Saved %@", self.scriptName];
    } else {
        [self setState:@"Save failed" color:UIColor.systemRedColor];
        if (showConsole) self.consoleView.text = error.localizedDescription ?: @"Unable to save script.";
    }
    return ok;
}

- (void)saveTapped {
    [self saveCurrent:YES];
}

- (void)newScript {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Lua Script"
                                                                   message:@"Use letters, numbers, dot, dash or underscore."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"script-name.lua";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        __strong typeof(weakSelf) self = weakSelf;
        NSString *name = [self normalizedName:alert.textFields.firstObject.text ?: @""];
        if (!name) {
            [self showMessage:@"Invalid name" message:@"Use letters, numbers, dot, dash or underscore only."];
            return;
        }
        NSString *path = [self pathForScript:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self showMessage:@"Already exists" message:name];
            return;
        }
        NSError *error = nil;
        if (![[self starterCode] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            [self showMessage:@"Create failed" message:error.localizedDescription ?: @"Unable to create script."];
            return;
        }
        [self loadScript:name];
        [self.codeView becomeFirstResponder];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseScript {
    NSArray<NSString *> *scripts = [self scriptNames];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Scripts"
                                                                   message:@"Choose a Lua script to edit."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSString *name in scripts) {
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            [weakSelf loadScript:name];
        }]];
        if (sheet.actions.count >= 30) break;
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"New Script" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf newScript];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.scriptButton;
        popover.sourceRect = self.scriptButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearConsole {
    self.consoleView.text = @"";
}

- (void)runEditorArguments:(NSArray<NSString *> *)arguments
                     state:(NSString *)state
                completion:(void (^)(int code, NSString *output))completion {
    [self.view endEditing:YES];
    [self.spinner startAnimating];
    [self setState:state color:UIColor.systemBlueColor];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int code = 0;
        NSString *output = NKLuaRunTool(arguments, &code);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (completion) completion(code, output ?: @"");
        });
    });
}

- (NSInteger)lineNumberFromOutput:(NSString *)output {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@":([0-9]+):" options:0 error:nil];
    NSTextCheckingResult *match = [re firstMatchInString:output options:0 range:NSMakeRange(0, output.length)];
    if (!match || match.numberOfRanges < 2) return NSNotFound;
    NSString *number = [output substringWithRange:[match rangeAtIndex:1]];
    return number.integerValue;
}

- (void)jumpToLine:(NSInteger)lineNumber {
    if (lineNumber <= 0) return;
    NSString *text = self.codeView.text ?: @"";
    NSUInteger location = 0;
    NSInteger current = 1;
    while (current < lineNumber && location < text.length) {
        NSRange newline = [text rangeOfString:@"\n" options:0 range:NSMakeRange(location, text.length - location)];
        if (newline.location == NSNotFound) return;
        location = NSMaxRange(newline);
        current++;
    }
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(MIN(location, text.length), 0)];
    self.codeView.selectedRange = lineRange;
    [self.codeView scrollRangeToVisible:lineRange];
    [self.codeView becomeFirstResponder];
}

- (void)checkTapped {
    if (![self saveCurrent:NO]) return;
    NSString *name = self.scriptName;
    __weak typeof(self) weakSelf = self;
    [self runEditorArguments:@[@"check", name] state:@"Checking…" completion:^(int code, NSString *output) {
        __strong typeof(weakSelf) self = weakSelf;
        self.consoleView.text = output;
        if (code == 0) {
            [self setState:@"Syntax OK" color:UIColor.systemGreenColor];
        } else {
            [self setState:@"Syntax error" color:UIColor.systemRedColor];
            NSInteger line = [self lineNumberFromOutput:output];
            if (line != NSNotFound) [self jumpToLine:line];
        }
    }];
}

- (void)runTapped {
    if (![self saveCurrent:NO]) return;
    NSString *name = self.scriptName;
    __weak typeof(self) weakSelf = self;
    [self runEditorArguments:@[@"check", name] state:@"Checking…" completion:^(int code, NSString *output) {
        __strong typeof(weakSelf) self = weakSelf;
        if (code != 0) {
            self.consoleView.text = output;
            [self setState:@"Syntax error" color:UIColor.systemRedColor];
            NSInteger line = [self lineNumberFromOutput:output];
            if (line != NSNotFound) [self jumpToLine:line];
            return;
        }
        [self runEditorArguments:@[@"run", name] state:@"Starting…" completion:^(int runCode, NSString *runOutput) {
            self.consoleView.text = runOutput;
            [self setState:(runCode == 0 ? @"Running" : @"Run failed")
                     color:(runCode == 0 ? UIColor.systemGreenColor : UIColor.systemRedColor)];
        }];
    }];
}

- (void)stopTapped {
    __weak typeof(self) weakSelf = self;
    [self runEditorArguments:@[@"stop"] state:@"Stopping…" completion:^(int code, NSString *output) {
        __strong typeof(weakSelf) self = weakSelf;
        self.consoleView.text = output;
        [self setState:(code == 0 ? @"Stopped" : @"Stop failed")
                 color:(code == 0 ? UIColor.secondaryLabelColor : UIColor.systemRedColor)];
    }];
}

- (void)logsTapped {
    __weak typeof(self) weakSelf = self;
    [self runEditorArguments:@[@"logs"] state:@"Loading logs…" completion:^(int code, NSString *output) {
        __strong typeof(weakSelf) self = weakSelf;
        self.consoleView.text = output;
        [self setState:(code == 0 ? @"Logs" : @"Log error")
                 color:(code == 0 ? UIColor.secondaryLabelColor : UIColor.systemRedColor)];
        if (self.consoleView.text.length) {
            NSRange end = NSMakeRange(self.consoleView.text.length - 1, 1);
            [self.consoleView scrollRangeToVisible:end];
        }
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.dirty) [self saveCurrent:NO];
}

@end
