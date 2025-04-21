#ifdef EC_STATIC
public import static "ecrt"
#else
public import "ecrt"
#endif

import "Key"
import "RootWindow"

#if defined(__EMSCRIPTEN__)
define target = "#canvas";
#endif

// Key to character mapping
static byte characters[2][128] =
{
   {
      128,128,'1','2','3','4','5','6','7','8','9','0','-','=',128,128,
      'q','w','e','r','t','y','u','i','o','p','[',']',128,128,'a','s',
      'd','f','g','h','j','k','l',';','\'','`',128,'\\','z','x','c','v',
      'b','n','m',',','.','/',128,'*',128,' ',128,128,128,128,128,128,
      128,128,128,128,128,128,128,'7','8','9','-','4','5','6','+','1',
      '2','3','0',128,128,128,128,128,128,128,128,128,128,128,128,128,
      128,128,'/',128,128,128,128,128,128,128,128,128,128,128,128,128,
      128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128
   },
   {
      128,128,'!','@','#','$','%','^','&','*','(',')','_','+',128,128,
      'Q','W','E','R','T','Y','U','I','O','P','{','}',128,128,'A','S',
      'D','F','G','H','J','K','L',':','"','~',128,'|','Z','X','C','V',
      'B','N','M','<','>','?',128,'*',128,' ',128,128,128,128,128,128,
      128,128,128,128,128,128,128,'7','8','9','-','4','5','6','+','1',
      '2','3','0',128,128,128,128,128,128,128,128,128,128,128,128,128,
      128,128,'/',128,128,128,128,128,128,128,128,128,128,128,128,128,
      128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128
   }
};

public struct Joystick
{
   int x,y,z;
   int rx,ry,rz;
   uint buttons;
//   int slider[2];
//   uint pov[4];
};

public class Interface
{
public:
   class_data const char * name;

   class_property const char * name
   {
      set { class_data(name) = value; }
      get { return class_data(name); }
   }

   // --- User Interface System ---
   virtual bool ::Initialize();
   virtual void ::Terminate();
   virtual bool ::ProcessInput(bool processAll);
   virtual void ::Wait();
   virtual void ::Lock(RootWindow window);
   virtual void ::Unlock(RootWindow window);
   virtual void ::SetTimerResolution(uint hertz);

   virtual const char ** ::GraphicsDrivers(int * numDrivers);
   virtual void ::EnsureFullScreen(bool * fullScreen);
   virtual void ::GetCurrentMode(bool * fullScreen, Resolution * resolution, PixelFormat * colorDepth, int * refreshRate);
   virtual bool ::ScreenMode(bool fullScreen, Resolution resolution, PixelFormat colorDepth, int refreshRate, bool * textMode);

   // --- RootWindow Creation ---
   virtual void * ::CreateRootWindow(RootWindow window);
   virtual void ::DestroyRootWindow(RootWindow window);

   // --- RootWindow manipulation ---
   virtual void ::SetRootWindowCaption(RootWindow window, const char * name);
   virtual void ::PositionRootWindow(RootWindow window, int x, int y, int w, int h, bool move, bool resize);
   virtual void ::OffsetWindow(RootWindow window, int * x, int * y);
   virtual void ::UpdateRootWindow(RootWindow window);
   virtual void ::SetRootWindowState(RootWindow window, WindowState state, bool visible);
   virtual void ::ActivateRootWindow(RootWindow window);
   virtual void ::OrderRootWindow(RootWindow window, bool topMost);
   virtual void ::SetRootWindowColor(RootWindow window);
   virtual void ::FlashRootWindow(RootWindow window);

   // --- Mouse-based window movement ---
   virtual void ::StartMoving(RootWindow window, int x, int y, bool fromKeyBoard);
   virtual void ::StopMoving(RootWindow window);

   // --- Mouse manipulation ---
   virtual void ::GetMousePosition(int *x, int *y);
   virtual void ::SetMousePosition(int x, int y);
   virtual void ::SetMouseRange(RootWindow window, Box box);
   virtual void ::SetMouseCapture(RootWindow window);

   // --- Mouse cursor ---
   virtual void ::SetMouseCursor(RootWindow window, SystemCursor cursor);

   // --- Caret manipulation ---
   virtual void ::SetCaret(int caretX, int caretY, int size);

   // --- Clipboard manipulation ---
   virtual void ::ClearClipboard();
   virtual bool ::AllocateClipboard(ClipBoard clipBoard, uint size);
   virtual bool ::SaveClipboard(ClipBoard clipBoard);
   virtual bool ::LoadClipboard(ClipBoard clipBoard);
   virtual void ::UnloadClipboard(ClipBoard clipBoard);

   // --- State based input ---
   virtual bool ::AcquireInput(RootWindow window, bool state);
   virtual bool ::GetMouseState(MouseButtons * buttons, int * x, int * y);
   virtual bool ::GetJoystickState(int device, Joystick joystick);
   virtual bool ::GetKeyState(Key key);

   // REVIEW: virtual bool ::SetIcon(RootWindow window, BitmapResource icon);
   virtual void ::GetScreenArea(RootWindow window, Box box);

   Key ::GetExtendedKey(Key key)
   {
      switch(key)
      {
         case keyPadHome:     return home;
         case keyPadUp:       return up;
         case keyPadPageUp:   return pageUp;
         case keyPadLeft:     return left;
         case keyPadRight:    return right;
         case keyPadEnd:      return end;
         case keyPadDown:     return down;
         case keyPadPageDown: return pageDown;
         case keyPadInsert:   return insert;
         case keyPadDelete:   return del;
         case enter:          return keyPadEnter;
         case leftControl:    return rightControl;
         case leftAlt:        return rightAlt;
         case slash:          return keyPadSlash;
         case numLock:        return numLock;
         case scrollLock:     return pauseBreak;
      }
      return 0;
   }

   char ::TranslateKey(Key key, bool shift)
   {
      int code = (int)key.code;
      return (code <= 127) ? characters[shift][code] : 0;
   }
};
