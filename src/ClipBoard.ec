#ifdef EC_STATIC
public import static "ecrt"
#else
public import "ecrt"
#endif

import "GuiApplication"

public class ClipBoard : struct
{
   public char * text;
   public void * handle;

   ~ClipBoard()
   {
      Unload();
   }

public:
   void Clear()
   {
      guiApp.interfaceDriver.ClearClipboard();
   }

   bool Allocate(uint size)
   {
      return guiApp.interfaceDriver.AllocateClipboard(this, size);
   }

   property char * memory { get { return text; } }

   bool Save()
   {
      return guiApp.interfaceDriver.SaveClipboard(this);
   }

   bool Load()
   {
      return guiApp.interfaceDriver.LoadClipboard(this);
   }

   void Unload()
   {
      guiApp.interfaceDriver.UnloadClipboard(this);
      text = null;
   }
}
