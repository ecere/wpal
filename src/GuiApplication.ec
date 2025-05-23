#define _Noreturn

#ifdef __EMSCRIPTEN__
#ifdef _DEBUG
// #define EMSCRIPTEN_DEBUG
#endif

#include <emscripten.h>
#include <emscripten/html5.h>
#endif

#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
#define property _property
#define new _new
#define class _class
#define uint _uint

#define Window    X11Window
#define Cursor    X11Cursor
#define Font      X11Font
#define Display   X11Display
#define Time      X11Time
#define KeyCode   X11KeyCode
#define Picture   X11Picture

#include <X11/Xutil.h>

#undef Window
#undef Cursor
#undef Font
#undef Display
#undef Time
#undef KeyCode
#undef Picture

#undef uint
#undef new
#undef property
#undef class

#endif

// REVIEW: Overlap with graphics system?
public enum PixelFormat // : byte MESSES UP GuiApplication
{
   pixelFormat4, pixelFormat8, pixelFormat444, pixelFormat555, pixelFormat565, pixelFormat888, pixelFormatAlpha, pixelFormatText, pixelFormatRGBA,
   pixelFormatA16, pixelFormatRGBAGL /* TODO: clarify pixelFormatRGBA vs. GL-ready */, pixelFormatETC2RGBA8
};
public enum Resolution : int
{
   resText80x25, res320x200, res320x240, res320x400, res360x480, res400x256, res400x300, res512x256, res512x384,
   res640x200, res640x350, res640x400, res640x480,  res720x348, res800x600, res856x480, res960x720, res1024x768,
   res1152x864, res1280x1024, res1600x1200, res768x480
};

import "Interface"
import "Cursor"
import "Timer"

/*static */bool guiApplicationInitialized = false;
GuiApplication guiApp;
int terminateX;

public class GuiApplication : Application
{
   int numDrivers;
   char ** driverNames;
   int numSkins;
   char ** skinNames;

   bool textMode;

   subclass(Interface) interfaceDriver;
   // subclass(Skin) currentSkin;

   // Desktop window
   RootWindow desktop;

   // Screen mode flags
   bool modeSwitching;
   bool fullScreenMode; // Needs to start at true for the desktop to resize

   bool fullScreen;
   Resolution resolution;
   PixelFormat pixelFormat;
   int refreshRate;

   const char * defaultDisplayDriver;

   Cursor systemCursors[SystemCursor];

   bool cursorUpdate;

   OldList customCursors;

   // RootWindow Timers
   OldList windowTimers;

   // Mouse events
   RootWindow prevWindow;            // Used for OnMouseLeave
   List<RootWindow> overWindows { }; // Used for OnMouseLeave
   RootWindow windowCaptured;

   // Mouse based moving & resizing
   RootWindow windowMoving;
   Point windowMovingStart;
   Point windowMovingBefore;
   Size windowResizingBefore;
   Point movingLast;
   bool windowIsResizing;
   bool resizeX, resizeEndX;
   bool resizeY, resizeEndY;

   // Mouse based scrolling
   RootWindow windowScrolling;
   Point windowScrollingBefore, windowScrollingStart;

   // Mouse cursors
   // TODO: Bitmap cursorBackground { };
   int cursorBackgroundX, cursorBackgroundY;
   int cursorBackgroundW, cursorBackgroundH;

   // Carets
   RootWindow caretOwner;

   // State based input
   RootWindow acquiredWindow;
   int acquiredMouseX, acquiredMouseY;

   Cursor currentCursor;

   uint errorLevel, lastErrorCode;

   bool processAll;

#if !defined(__EMSCRIPTEN__)
   Mutex waitMutex {};
#endif
   bool waiting;
#if !defined(__EMSCRIPTEN__)
   Mutex lockMutex {};
#endif

   RootWindow interimWindow;
   bool caretEnabled;

   char appName[1024];
   uint timerResolution;

   Size virtualScreen;
   Point virtualScreenPos;

   int64 mainThread;
   void * xGlobalDisplay;

   GuiApplication()
   {
      SystemCursor c;

#if !defined(__EMSCRIPTEN__)
      mainThread = GetCurrentThreadID();
#endif
      if(!guiApp)
         guiApp = this;

      strcpy(appName, $"ECERE Application");

      processAll = true;

      // TODO:
      // customCursors.offset = OFFSET(Cursor, prev);
      windowTimers.offset = (uint)(uintptr)&((Timer)0).prev;

      for(c = 0; c<SystemCursor::enumSize; c++)
         systemCursors[c] = Cursor { systemCursor = c; };

      return true;
   }

   ~GuiApplication()
   {
      SystemCursor c;

      if(desktop)
         desktop.Destroy(0);
      delete desktop;
      customCursors.Clear();

#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
      if(xGlobalDisplay)
         XUnlockDisplay(xGlobalDisplay);
#endif

#if !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
      // Because destruction of app won't be from main thread
      if(guiApplicationInitialized)
         lockMutex.Release();
#endif

      if(interfaceDriver)
      {
         interfaceDriver.Terminate();
      }

      // interfaceDrivers.Free(null);
      delete driverNames;

      // skins.Free(null);
      delete skinNames;

      for(c = 0; c<SystemCursor::enumSize; c++)
         delete systemCursors[c];

      // TODO: UnapplySkin(class(RootWindow));

      // Stop all timers
      {
         Timer timer, nextTimer;
         for(timer = windowTimers.first; timer; timer = nextTimer)
         {
            nextTimer = timer.next;
            timer.Stop();
         }
      }

      if(guiApp == this)
         guiApp = null;
   }

   bool UpdateTimers()
   {
      bool result = false;
      Time time = GetTime();
      Timer timer;

      for(timer = windowTimers.first; timer; timer = timer.next)
         timer.dispatched = false;
      for(;;)
      {
         for(timer = windowTimers.first; timer; timer = timer.next)
         {
            if(!timer.dispatched)
            {
               if((timer.delay - (Seconds)(time - timer.lastTime)) < Seconds { 0.00001 })
               {
                  incref timer;
                  timer.lastTime = time;
                  if(timer.DelayExpired(timer.window))
                     result = true;
                  timer.dispatched = true;
                  //delete timer;
                  eInstance_DecRef(timer);
                  break;
               }
            }
         }
         if(!timer) break;
      }
      return result;
   }

   // --- Mouse-based window movement ---
   void SetCurrentCursor(RootWindow window, Cursor cursor)
   {
      currentCursor = cursor;
      if(cursor)
      {
         if(fullScreenMode && cursor.bitmap)
            interfaceDriver.SetMouseCursor(window ? window : desktop, (SystemCursor)-1);
         else
         {
            interfaceDriver.SetMouseCursor(window ? window : desktop, cursor.systemCursor);
            // TODO: cursorBackground.Free();
         }
      }
      cursorUpdate = true;
   }

   void PreserveAndDrawCursor()
   {
      /* TODO:
      if(!acquiredWindow && cursorUpdate && currentCursor && currentCursor.bitmap)
      {
         Bitmap bitmap = currentCursor.bitmap;
         int mouseX, mouseY;
         Surface surface;
         Box against = {0,0, desktop.size.w-1,desktop.size.h-1};
         Box box = {0, 0, bitmap.width, bitmap.height};
         Display display = desktop.display;
         DisplayFlags flags = display.flags;

         interfaceDriver.GetMousePosition(&mouseX, &mouseY);

         mouseX -= currentCursor.hotSpotX;
         mouseY -= currentCursor.hotSpotY;

         // Preserve Background
         if(!flags.flipping)
         {
            cursorBackgroundX = mouseX;
            cursorBackgroundY = mouseY;
            cursorBackgroundW = bitmap.width;
            cursorBackgroundH = bitmap.height;
            display.Grab(cursorBackground, mouseX, mouseY, cursorBackgroundW, cursorBackgroundH);
         }

         box.ClipOffset(&against, mouseX, mouseY);

         if(!flags.flipping)
            display.StartUpdate();
         // Display Cursor
         surface = display.GetSurface(mouseX, mouseY, box);
         if(surface)
         {
            surface.foreground = white;
            surface.Blit(bitmap, 0,0, 0,0,
               bitmap.width, bitmap.height);
            delete surface;

            if(!flags.flipping)
            {
               box.left += mouseX;
               box.right += mouseX;
               box.top += mouseY;
               box.bottom += mouseY;
               display.Update(box);
            }
         }
         if(!flags.flipping)
            display.EndUpdate();
      }
      */
   }

   void RestoreCursorBackground()
   {
      /* TODO:
      // Restore Cursor Background
      if(cursorBackground && desktop.active)
      {
         Box box = {0, 0, cursorBackgroundW-1,cursorBackgroundH-1};
         Box against = {0,0, desktop.size.w-1,desktop.size.h-1};
         Surface surface;

         box.ClipOffset(against, cursorBackgroundX, cursorBackgroundY);
         if((surface = desktop.display.GetSurface(cursorBackgroundX, cursorBackgroundY, &box)))
         {
            surface.Blit(cursorBackground, 0, 0, 0,0, cursorBackgroundW, cursorBackgroundH);
            delete surface;
         }
      }
      */
   }

   bool IsModeSwitching()
   {
      return modeSwitching;
   }

   public bool SetDesktopPosition(int x, int y, int w, int h, bool moveChildren)
   {
      bool result = true;
      bool windowResized = desktop.size.w != w || desktop.size.h != h;
      bool windowMoved = desktop.clientStart.x != x || desktop.clientStart.y != y;

      if((windowResized || windowMoved) && moveChildren)
      {
         RootWindow child;
         desktop.Position(x, y, w, h, true, true, true, true, false, false);

         // Maximized native decorations windows suffer when we drag the dock around, so remaximize them
         // It's a little jumpy, but oh well.

         // Made this Windows only as it was causing occasional wrong stacking of windows in X11/Cinnamon
         // when switching debugged app from full-screen

         for(child = desktop.children.first; child; child = child.next)
         {
            if(child.nativeDecorations && child.rootWindow == child && child.state == maximized)
            {
#if defined(__WIN32__)
               child.state = normal;
               child.state = maximized;
#else
               if(child.active)
               {
                  child.state = normal;
                  child.state = maximized;
               }
               else
                  child.requireRemaximize = true;
#endif
            }
         }
         /*for(child = desktop.children.first; child; child = child.next)
         {
            if(!child.systemParent)
            {
               if(child.anchored)
               {
                  int x, y, w, h;
                  child.ComputeAnchors(
                     child.ax, child.ay, child.aw, child.ah,
                     &x, &y, &w, &h);
                  child.Position(x, y, w, h, true, true, true, true, false);
               }
               if(child.state == Maximized)
               {
                  child.x = desktop.x;
                  child.y = desktop.y;
                  child.ComputeAnchors(,
                     A_LEFT,A_LEFT,A_OFFSET,A_OFFSET,
                     &x, &y, &w, &h);
                  child.Position(, x, y, w, h, false, true, true, true, false);
               }
            }
         }*/

         desktop.UpdatedDisplayPosition(windowResized);
      }
      else
         desktop.SetPosition(x, y, w, h, false, false, false);
      return result;
   }

   void SetAppFocus(bool state)
   {
      // Shouldn't be property here
      desktop.active = state;
   }

   /* TODO:
   bool SelectSkin(const char * skinName)
   {
      bool result = false;
      subclass(Skin) skin;
      OldLink link;

      for(link = class(Skin).derivatives.first; link; link = link.next)
      {
         skin = link.data;
         if(skin.name && !strcmp(skin.name, skinName))
            break;
      }
      if(!link) skin = null;

      if(skin)
      {
         if(skin != currentSkin || !currentSkin)
         {
            // Try finding a driver to support this mode
            if(skin.textMode != textMode)
            {
               return false;
            }
            else
            {
               bool needReload = false;

               if(!modeSwitching && currentSkin)
               {
                  modeSwitching = true;
                  desktop.UnloadGraphics(true);
                  needReload = true;
               }

               UnapplySkin(class(RootWindow));

               currentSkin = skin;

               ApplySkin(class(RootWindow), skin.name, null);

               if(needReload)
               {
                  if(desktop.SetupDisplay())
                     if(desktop.LoadGraphics(false, true))
                        result = true;
                  modeSwitching = false;
               }
               else
                  result = true;
            }
         }
         else
            result = true;
      }
      return result;
   }
   */

   void Initialize(bool switchMode)
   {
      // TODO:
      // if(!initialized && eClass_IsDerived(__ecereModule->app->module.inst.class, guiApplicationClass))
      if(!guiApplicationInitialized)
      {
         const char * defaultDriver = null;
#if defined(WPAL_VANILLA) || defined(ECERE_ONEDRIVER)
         char * driver = null;
#else

         // char * driver = getenv("ECERE_DRIVER");
         char * driver = null;
         static char driverStorage[1024];
         GetEnvironment("ECERE_DRIVER", driverStorage, sizeof(driverStorage));
         if(driverStorage[0]) driver = driverStorage;
#endif
         guiApplicationInitialized = true;

         fullScreenMode = true; // Needs to start at true for the desktop to resize
         // Set this to true earlier so we can override it!
         //processAll = true;

         errorLevel = 2;

#if !defined(__EMSCRIPTEN__)
         lockMutex.Wait();
#endif
/*#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__)
         if(xGlobalDisplay)
            XLockDisplay(xGlobalDisplay);
#endif*/

         // Setup Desktop
         if(!desktop)
         {
            desktop = RootWindow { nativeDecorations = false };
            incref desktop;
            incref desktop;
            desktop.childrenOrder.circ = true;
            desktop.childrenCycle.circ = true;
            // TODO: desktop.background = blue;
            desktop.rootWindow = desktop;
            desktop.cursor = GetCursor(arrow);
            desktop.caption = appName;
            *&desktop.visible = true;
            desktop.position = Point { };
#if !defined(__EMSCRIPTEN__)
            desktop.mutex = Mutex { };
#endif
            desktop.created = true;
         }

   #if defined(__WIN32__)
         {
            if(driver)
               defaultDriver = driver;
            else if((this.isGUIApp & 1) && !textMode)
               defaultDriver = "GDI";
            else
               defaultDriver = "Win32Console";
         }
   #elif defined(__APPLE__)
         {
            if (driver)
               defaultDriver = driver;
            else
               defaultDriver = "X"; //"CocoaOpenGL";
         }
   #elif defined(__ANDROID__)
         {
            if(driver)
               defaultDriver = driver;
            else
               defaultDriver = "OpenGL";
         }
   #elif defined(__EMSCRIPTEN__)
         {
            if(driver)
               defaultDriver = driver;
            else
               defaultDriver = "OpenGL";
         }
   #else
         if((this.isGUIApp & 1) && !textMode)
         {
            char * display = getenv("DISPLAY");

            if(!display || !display[0] || !SwitchMode(false, "X", 0, 0, 0, null, true))
               defaultDriver = "NCurses";
               // SwitchMode(true, "NCurses", 0, PixelFormatText, 0, null, true);
            else if(!driver)
               defaultDriver = "X";
            else
               defaultDriver = driver;
         }
         else
            defaultDriver = "NCurses";
   #endif
         if(switchMode)
         {
            if(defaultDriver)
               SwitchMode(false, defaultDriver, 0, 0, 0, null, true);
            else
            {
            /*
         #if defined(__WIN32__)
               SwitchMode(true, "Win32Console", 0, PixelFormatText, 0, null, true);
         #endif
            */

         #if defined(__DOS__)
               SwitchMode(true, "SVGA", Res640x480, PixelFormat8, 0, null, true);
         #endif

         #if defined(__APPLE__)
               // SwitchMode(true, "X" /*"CocoaOpenGL"*/, 0, 0, 0, null, true);
         #endif

         #if defined(__unix__)
         #if defined(ECERE_MINIGLX)
               SwitchMode(true, "OpenGL", 0, 0, 0, null, true);
         #endif
         #endif
            }
            /*if(!interfaceDriver)
               guiApplicationInitialized = false;*/
         }
         else
            defaultDisplayDriver = defaultDriver;
      }
   }

public:
   virtual bool Init(void);
   virtual bool Cycle(bool idle);
   virtual void Terminate(void);

   void Main(void)
   {
      RootWindow window;

#ifdef __EMSCRIPTEN__
#ifdef EMSCRIPTEN_DEBUG
      emscripten_log(EM_LOG_CONSOLE, "GuiApplication::Main\n");
      {
         bool found = false;
         const char * resourcesFile = "resources.ear";
         FileListing listing { "/" };
         // emscripten_log(EM_LOG_CONSOLE, "GuiApplication::Main -- listing files @/:\n");
         // while(listing.Find())
         //    emscripten_log(EM_LOG_CONSOLE, "      %s\n", listing.name);
         while(listing.Find())
         {
            if(!strcmp(listing.name, resourcesFile))
            {
               found = true;
               break;
            }
         }
         if(!found)
            emscripten_log(EM_LOG_CONSOLE, "warning: %s not found!\n", resourcesFile);
      }
#endif
      {
         int w = 0, h = 0;
         double dw = 0, dh = 0;
         /*
         emscripten_log(EM_LOG_CONSOLE, "GuiApplication::Main -- sizeof(size_t): %d\n", sizeof(size_t));
         emscripten_log(EM_LOG_CONSOLE, "GuiApplication::Main -- sizeof(void *): %d\n", sizeof(void *));
         emscripten_log(EM_LOG_CONSOLE, "GuiApplication::Main -- sizeof(double): %d\n", sizeof(double));
         emscripten_log(EM_LOG_CONSOLE, "GuiApplication::Main -- sizeof(unsigned int): %d\n", sizeof(unsigned int));
         */

         emscripten_get_element_css_size(target, &dw, &dh);
         w = (int)dw, h = (int)dh;
#ifdef EMSCRIPTEN_DEBUG
         printf("getElementCssSize  --guiapplication--  %4dx%-4d\n", w, h);
         {
            int w = 0, h = 0;
            emscripten_get_screen_size(&w, &h);
            printf("getScreenSize      %4dx%-4d\n", w, h);
         }
#endif
         if(w && h)
         {
            emscripten_set_canvas_element_size(target, w, h);
            guiApp.desktop.ExternalPosition(0, 0, w, h);
            if(guiApp.desktop.display && guiApp.desktop.display.displaySystem)
               guiApp.desktop.display.Resize(w, h);
         }
      }
#endif

#ifdef EMSCRIPTEN_DEBUG
      printf("before init\n");

      /*
      {
         // HTMLCanvasElement *canvas;
         char * id = "canvas";
         char * text = "test";
         char * context = "2d";
         EM_ASM({
            document.getElementById(UTF8ToString($0)).getContext($1).fillText(UTF8ToString($2), $3, $4);
         },
               id, context, text, 32, 164);
      }
      */
      // emscripten_run_script("document.getElementById(UTF8ToString('canvas')).getContext('2d').fillText('test', 32, 164);");
#endif

      if(Init())
      {
         if(desktop)
         {
            // better solution when designing tab order/activated window etc, why do windows move in the list?
            while(true)
            {
               for(window = desktop.children.first; window; window = window.next)
               {
                  if(window.autoCreate && !window.created)
                  {
#ifdef EMSCRIPTEN_DEBUG
                     printf("   inside window.Create()\n");
#endif
                     if(window.Create())
                     {
#ifdef EMSCRIPTEN_DEBUG
                        printf("      created\n");
#endif
                        break;
                     }
#ifdef EMSCRIPTEN_DEBUG
                     else
                        printf("      failed?\n");
#endif
                  }
               }
               if(!window) break;
            }
         }

#ifdef __EMSCRIPTEN__
#ifdef EMSCRIPTEN_DEBUG
         printf("emscripten_set_main_loop\n");
#endif
         emscripten_set_main_loop(emscripten_main_loop_callback, 0 /*60*/, 1);
#endif

         if(desktop)
         {
            int terminated = 0;
            incref desktop;

            ProcessInput(true);
            while(desktop && interfaceDriver)
            {
               bool wait;
               RootWindow child;
               if(terminateX != terminated)
               {
                  terminated = terminateX;
                  desktop.Destroy(0);
                  if(desktop.created)
                  {
                     terminated = 0;
                     terminateX = 0;
                     //printf("Resetting terminate X to 0\n");
                  }
               }

               for(child = *&desktop.children.first; child; child = *&child.next)
                  if(*&child.created && *&child.visible && !(*&child.style).interim)
                     break;
               if(!child) break;

#if !defined(__EMSCRIPTEN__)
               for(window = *&desktop.children.first; window; window = *&window.next)
                  if(window.mutex) window.mutex.Wait();
#endif
               UpdateDisplay();
#if !defined(__EMSCRIPTEN__)
               for(window = desktop.children.first; window; window = window.next)
                  if(window.mutex) window.mutex.Release();
#endif
               wait = !ProcessInput(true);
#if !defined(__EMSCRIPTEN__)
#ifdef _DEBUG
               if(lockMutex.owningThread != GetCurrentThreadID())
                  PrintLn("WARNING: ProcessInput returned unlocked GUI!");
#endif
#endif
               if(!Cycle(wait))
                  wait = false;

               if(wait)
                  Wait();
               else
               {
#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
                  if(xGlobalDisplay)
                     XUnlockDisplay(xGlobalDisplay);
#endif

#if !defined(__EMSCRIPTEN__)
                  lockMutex.Release();
                  lockMutex.Wait();
#endif

#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
                  if(xGlobalDisplay)
                     XLockDisplay(xGlobalDisplay);
#endif
               }
            }
            eInstance_DecRef(desktop);
         }
      }
      Terminate();

#if defined(__ANDROID__)
      // Because destruction of GuiApp won't be from main thread
      lockMutex.Release();
#endif
   }

   void Wait(void)
   {
      static Time lastTime = 0;

      Time time = GetTime();
      if(!lastTime) lastTime = time;

      if((double)(time - lastTime) > 1.0 / Max(18.2, (double)timerResolution))
      {
         lastTime = time;
         return;
      }

#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
      if(xGlobalDisplay)
         XUnlockDisplay(xGlobalDisplay);
#endif

#if !defined(__EMSCRIPTEN__)
      lockMutex.Release();

      waitMutex.Wait();
#endif
      waiting = true;
      if(interfaceDriver)
         interfaceDriver.Wait();
      waiting = false;
#if !defined(__EMSCRIPTEN__)
      waitMutex.Release();

      lockMutex.Wait();
#endif

#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
      if(xGlobalDisplay)
         XLockDisplay(xGlobalDisplay);
#endif
      lastTime = time;
   }

   bool ProcessInput(bool useProcessAll)
   {
      if(interfaceDriver)
      {
         bool result = 0;

         /*
         result = interfaceDriver.ProcessInput(useProcessAll && processAll);
         if(!desktop || !interfaceDriver) return;
         {
            bool wait;
            RootWindow child;
            for(child = app.desktop.children.first; child; child = child.next)
               if(child.created && child.visible)
                  break;
            if(!child) return result;
         }

         result |= UpdateTimers();
         result |= ProcessFileNotifications();
         */

         result |= ProcessFileNotifications();
         result |= UpdateTimers();
         result |= interfaceDriver.ProcessInput(useProcessAll && processAll);

         return result;
      }
      return false;
   }

   void UpdateDisplay(void)
   {
      if(interfaceDriver)
      {
#if defined(__EMSCRIPTEN__)
         if(true)
#else
         if(fullScreenMode) // REVIEW: && desktop.display)
#endif
         {
#if !defined(__EMSCRIPTEN__)
            desktop.mutex.Wait();
#endif
            if(desktop.active)
               desktop.UpdateFullScreenDisplay();
#if !defined(__EMSCRIPTEN__)
            desktop.mutex.Release();
#endif
         }
         else
         {
            RootWindow window;

            for(window = *&desktop.children.first; window; window = *&window.next)
            {
#if !defined(__EMSCRIPTEN__)
               if(window.mutex) window.mutex.Wait();
#endif
               if(window.visible && window.dirty && window.created)
               {
                  // Logf("Updating %s\n", window.name);
                  interfaceDriver.Lock(window);
                  window.UpdateDisplayLocked();
                  interfaceDriver.Unlock(window);
                  /*
                  Log("--------------\n");
                  usleep(1000000);
                  */
               }
#if !defined(__EMSCRIPTEN__)
               if(window.mutex) window.mutex.Release();
#endif
            }
         }
      }
   }

   void WaitEvent(void)
   {
#if !defined(__EMSCRIPTEN__)
      getEventSemaphore().Wait();
#endif
   }

   void SignalEvent(void)
   {
#if !defined(__EMSCRIPTEN__)
      getEventSemaphore().Release();
#endif
   }

   // TODO: Might want to make this private with simpler public version?
   bool SwitchMode(bool fullScreen, const char * driverName, Resolution resolution, PixelFormat colorDepth, int refreshRate, const char * skinName, bool fallBack)
   {
      bool result = false;
      OldLink link;
      const char * fbDriver;
      bool fbFullScreen = 0;
      Resolution fbResolution = 0;
      PixelFormat fbColorDepth = 0;
      int fbRefreshRate = 0;
      subclass(Interface) inter;
      /*
      subclass(Skin) skin = null;

      if(skinName)
      {
         OldLink link;

         for(link = class(Skin).derivatives.first; link; link = link.next)
         {
            skin = link.data;
            if(skin.name && !strcmp(skin.name, skinName))
               break;
         }
         if(!link) skin = null;
      }
      */

      Initialize(false);

      fbDriver = defaultDisplayDriver;
      inter = interfaceDriver;

      if(interfaceDriver)
         interfaceDriver.GetCurrentMode(&fbFullScreen, &fbResolution, &fbColorDepth, &fbRefreshRate);

      if(!driverName && !interfaceDriver)
         driverName = defaultDisplayDriver;

      if(driverName) // || (skin && skin.textMode != textMode))
      {
         for(link = class(Interface).derivatives.first; link; link = link.next)
         {
            bool foundDriver = false;
            int c, numDrivers = 0;
            const char ** graphicsDrivers;
            inter = link.data;

            graphicsDrivers = inter.GraphicsDrivers(&numDrivers);

            for(c=0; c<numDrivers; c++)
               if(!driverName || !strcmp(driverName, graphicsDrivers[c]))
               {
                  //if(!skin || skin.textMode == IsDriverTextMode(graphicsDrivers[c]))
                  {
                     driverName = graphicsDrivers[c];
                     foundDriver = true;
                     break;
                  }
               }
            if(foundDriver)
               break;
         }
         if(!link)
            inter = null;
      }

      /*
      if(driverName)
      {
#if defined(__WIN32__)
#if !defined(WPAL_VANILLA)
         if(!strcmp(driverName, "Win32Console")) inter = (subclass(Interface))class(Win32ConsoleInterface); else
#endif
         inter = (subclass(Interface))class(Win32Interface);
#else
         if(!strcmp(driverName, "X")) inter = (subclass(Interface))class(XInterface);
         else inter = (subclass(Interface))class(NCursesInterface);
#endif
      }
      */

      if(interfaceDriver && (!driverName || (fbDriver && !strcmp(fbDriver, driverName))) &&
         fullScreen == fbFullScreen &&
         (!resolution || resolution == fbResolution) &&
         (!colorDepth || colorDepth == fbColorDepth) &&
         (!refreshRate || refreshRate == fbRefreshRate) /*&&
         (currentSkin && (!skinName || !strcmp(currentSkin.name, skinName)))*/)
         result = true;
#if defined(__EMSCRIPTEN__)
      else if(interfaceDriver && (!driverName || (fbDriver && !strcmp(fbDriver, driverName))) &&
         fullScreen != fbFullScreen &&
         (!resolution || resolution == fbResolution) &&
         (!colorDepth || colorDepth == fbColorDepth) &&
         (!refreshRate || refreshRate == fbRefreshRate) /*&&
         (currentSkin && (!skinName || !strcmp(currentSkin.name, skinName)))*/)
      {
         if(inter.ScreenMode(fullScreen, resolution, colorDepth, refreshRate, &textMode))
            this.fullScreen = fullScreen;
         result = true;
      }
#endif
      else if(inter)
      {
         bool wasFullScreen = fullScreenMode;
         // subclass(Skin) oldSkin = currentSkin;

         textMode = false;
         modeSwitching = true;

         if(interfaceDriver)
            desktop.UnloadGraphics(true);

         if(inter != interfaceDriver)
         {
            if(interfaceDriver)
            {
               interfaceDriver.Terminate();
            }
            result = inter.Initialize();
         }
         else
            result = true;
         if(result)
         {
            result = false;

            interfaceDriver = inter;
            interfaceDriver.SetTimerResolution(timerResolution);
            inter.EnsureFullScreen(&fullScreen);
            fullScreenMode = fullScreen;

            if((!wasFullScreen && !fullScreen) ||
               inter.ScreenMode(fullScreen, resolution, colorDepth, refreshRate, &textMode))
            {
               if(!fbDriver || (driverName && strcmp(fbDriver, driverName)))
                  defaultDisplayDriver = driverName;

               /*if(!skinName || !SelectSkin(skinName))
               {
                  if(!currentSkin || currentSkin.textMode != textMode ||
                     !SelectSkin(currentSkin.name))
                  {
                     OldLink link;
                     subclass(Skin) skin = null;

                     for(link = class(Skin).derivatives.first; link; link = link.next)
                     {
                        skin = link.data;
                        if(skin.textMode == textMode)
                           break;
                     }
                     if(!link) skin = null;

                     if(skin)
#if !defined(__ANDROID__)
                        SelectSkin(skin.name);
#else
                        currentSkin = skin;
#endif
                  }
               }*/

               if(/*currentSkin && */desktop.SetupDisplay())
               {
                  desktop.active = true;

                  if(fullScreen)
                     desktop.ZeroPositionLocked();

                  if(desktop.LoadGraphics(false, false)) //oldSkin != currentSkin))
                  {
                     if(fbDriver)
                        desktop.UpdateDisplay();
                     this.fullScreen = fullScreen;
                     result = true;
                  }
               }
            }
         }
         modeSwitching = false;
         if(!result)
            LogErrorCode(modeSwitchFailed, driverName ? driverName : defaultDisplayDriver);
      }
      else
         LogErrorCode(driverNotSupported, driverName ? driverName : defaultDisplayDriver);

      if(!result && fallBack && fbDriver)
      {
         if(!SwitchMode(fbFullScreen, fbDriver, fbResolution, fbColorDepth, fbRefreshRate, null, false))
            Log($"Error falling back to previous video mode.\n");
      }
      return result;
   }

   void Lock(void)
   {
#if !defined(__EMSCRIPTEN__)
      lockMutex.Wait();
#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
      if(xGlobalDisplay)
         XLockDisplay(xGlobalDisplay);
#endif
#endif
   }

   void Unlock(void)
   {
#if !defined(__EMSCRIPTEN__)
#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
      if(xGlobalDisplay)
         XUnlockDisplay(xGlobalDisplay);
#endif
      lockMutex.Release();
#endif
   }

   void LockEx(int count)
   {
#if !defined(__EMSCRIPTEN__)
      int i;
      for(i = 0; i < count; i++)
      {
         lockMutex.Wait();
#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
         if(xGlobalDisplay)
            XLockDisplay(xGlobalDisplay);
#endif
      }
#endif
   }

   int UnlockEx(void)
   {
      int count = 0;
#if !defined(__EMSCRIPTEN__)
      int i;
      count = lockMutex.owningThread == GetCurrentThreadID() ? lockMutex.lockCount : 0;
      for(i = 0; i < count; i++)
      {
#if (defined(__unix__) || defined(__APPLE__)) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
         if(xGlobalDisplay)
            XUnlockDisplay(xGlobalDisplay);
#endif
         lockMutex.Release();
      }
#endif
      return count;
   }

   Cursor GetCursor(SystemCursor cursor)
   {
      return systemCursors[cursor];
   }

   bool GetKeyState(Key key)
   {
      return interfaceDriver.GetKeyState(key);
   }

   bool GetMouseState(MouseButtons * buttons, int * x, int * y)
   {
      return interfaceDriver.GetMouseState(buttons, x, y);
   }

   // Properties
   property const char * appName
   {
      set
      {
         strcpy(appName, value);
         if(desktop) desktop.text = appName;
      }
      get
      {
         return (const char *)(this ? appName : null);
      }
   };
#if !defined(__EMSCRIPTEN__)
   property Semaphore semaphore { get { return getEventSemaphore(); } };
#endif
   property bool alwaysEmptyInput{ set { processAll = value; } get { return processAll; } };
   property bool fullScreen
   {
      set
      {
         SwitchMode(value, defaultDisplayDriver, resolution,
            pixelFormat, refreshRate, /*currentSkin ? currentSkin.name : */null, true);
      }
      get { return this ? fullScreen : false; }
   };
   property const char * driver
   {
      set
      {
         SwitchMode( fullScreen, value, resolution, pixelFormat, refreshRate,
            /*currentSkin ? currentSkin.name : */null, true);
       }
       get { return this ? defaultDisplayDriver : null; }
   };
   property Resolution resolution
   {
      set
      {
         SwitchMode(fullScreen, defaultDisplayDriver, value, pixelFormat, refreshRate,
            /*currentSkin ? currentSkin.name : */null, true);
      }
      get { return this ? resolution : 0; }
   };
   property PixelFormat pixelFormat
   {
      set
      {
         SwitchMode(fullScreen, defaultDisplayDriver, resolution,
            pixelFormat, refreshRate, /*currentSkin ? currentSkin.name : */null, true);
      }
      get { return this ? pixelFormat : 0; }
   };
   property int refreshRate
   {
      set
      {
         SwitchMode(fullScreen, defaultDisplayDriver, resolution,
            pixelFormat, refreshRate, /*currentSkin ? currentSkin.name : */null, true);
      }
      get { return this ? refreshRate : 0; }
   };
   /*
   property const char * skin
   {
      set { SelectSkin(value); }
      get { return (this && currentSkin) ? currentSkin.name : null; }
   };
   */
   property bool textMode
   {
      set { textMode = value; }     // TODO: Implement switching
      get { return this ? textMode : false; }
   };
   property RootWindow desktop { get { return this ? desktop : null; } };
   property const char ** drivers { get { return null; } };
   // property const char * const * skins { get { return null; } };
   // property subclass(Skin) currentSkin { get { return this ? currentSkin : null; } };
   property int numDrivers { get { return 0; } };
   // property int numSkins { get { return 0; } };
   property uint timerResolution
   {
      set { timerResolution = value; if(interfaceDriver) interfaceDriver.SetTimerResolution(value); }
   };
   property RootWindow acquiredWindow { get { return acquiredWindow; } };

   property void * xGlobalDisplay { get { return xGlobalDisplay; } }
};

#ifdef __EMSCRIPTEN__
private void emscripten_main_loop_callback()
{
   static bool init = true;
   if(init)
   {
      int w = 0, h = 0;
      double dw = 0, dh = 0;
      emscripten_get_element_css_size(target, &dw, &dh);
      w = (int)dw, h = (int)dh;
#ifdef EMSCRIPTEN_DEBUG
      printf("emscripten_main_loop_callback/init\n");
      printf("getElementCssSize  %4dx%-4d\n", w, h);
#endif
      if(w && h)
      {
      // emscripten_set_canvas_element_size(target, w, h);
         guiApp.desktop.ExternalPosition(0, 0, w, h);
         if(guiApp.desktop.display && guiApp.desktop.display.displaySystem)
            guiApp.desktop.display.Resize(w, h);
         init = false;
      }
   }
   guiApp.ProcessInput(false);
   guiApp.Cycle(false);
   guiApp.UpdateDisplay();
}
#endif

/*
#if !defined(WPAL_VANILLA)
struct
Euler compass;

public void QueryCompass(Euler value)
{
   value = compass;
}
#endif
*/
