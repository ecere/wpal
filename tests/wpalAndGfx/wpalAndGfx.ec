import "ecrt"
import "wpal"
import "gfx"

define gfxApp = (WPALGFXApp)__thisModule.application;

subclass(DisplayDriver) dDriver;
DisplaySystem ds;
void * xVisualInfo, * glxFBConfig;

class GfxWindow : RootWindow
{
   borderStyle = sizable;
   hasClose = true;
   hasMaximize = true;
   hasMinimize = true;
   size = { 1024, 768 };
   caption = "WPAL and GFX Test";

   Display display;
   FontResource fntDejaVu { faceName = "DejaVu Sans", size = 18, bold = true, outlineSize = 3 };
   Color background; background = teal;
   GfxResourceManager resManager { };

   bool OnLoadDisplay()
   {
      bool result;

      if(!ds)
      {
         ds = DisplaySystem { xGlobalDisplay = gfxApp.xGlobalDisplay };
         incref ds;
         if(!ds.Create(dDriver.name, systemHandle, false))
         {
            PrintLn("Failure to create OpenGL display system");
            delete ds;
            return false;
         }
      }

      display = Display { xVisualInfo = xVisualInfo, glxFBConfig = glxFBConfig };
      resManager.display = display;
      incref display;

      if(!display.Create(ds, systemHandle))
      {
         PrintLn("Failure to create OpenGL display");
         delete display;
         return false;
      }

      display.Lock(false);
      fntDejaVu.manager = resManager;
      result = OnLoadGraphics();
      display.Unlock();
      return result;
   }
   virtual bool OnLoadGraphics() { return true; }

   void OnUnloadDisplay()
   {
      display.Lock(false);
      OnUnloadGraphics();
      display.Unlock();
      delete display;
   }

   virtual void OnUnloadGraphics();

   void OnResize(int width, int height)
   {
      display.Lock(true);
      display.Resize(width, height);
      display.Unlock();
   }

   void OnRedrawDisplay()
   {
      Surface surface;
      display.Lock(true);
      display.StartUpdate();

      surface = display.GetSurface(0, 0, null);
      surface.foreground = white;
      surface.background = background;
      surface.outlineColor = black;
      surface.font = fntDejaVu.font;

      OnRedraw(surface);

      delete surface;

      display.Update(null);
      display.EndUpdate();
      display.Unlock();
   }

   virtual void OnRedraw(Surface surface)
   {
      surface.Clear(colorAndDepth);
      surface.WriteTextf(10, 10, "Hello, WPAL & GFX!");
   }
}

class WPALGFXApp : GuiApplication
{
   bool Init()
   {
      dDriver = GetDisplayDriver("OpenGL");
      xVisualInfo = chooseGLXVisual(xGlobalDisplay, &glxFBConfig, false);
      if(desktop)
      {
         RootWindow c;
         for(c = desktop.firstChild; c; c = c.next)
            c.xVisualInfo = xVisualInfo;
      }
      return GuiApplication::Init();
   }

   void Terminate()
   {
      delete ds;
      GuiApplication::Terminate();
   }
}
