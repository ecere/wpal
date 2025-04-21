import "wpalAndGfx"

Camera camera
{
   fixed,
   position = Vector3D { 0, 0, -300 },
   orientation = Euler { 0, 0, 0 },
   fov = 53;
};

Light light
{
   diffuse = lightCoral;
   orientation = Euler { pitch = 10, yaw = 30 };
};

class Hello3D : GfxWindow
{
   caption = "Hello, 3D";

   Cube cube { };
   Material material { diffuse = white/*, ambient = blue*//*, specular = red, power = 8*/, opacity = 0.5f/*, flags = { translucent = true, doubleSided = true }*/ };

   bool OnLoadGraphics()
   {
      cube.Create(display.displaySystem);
      cube.mesh.ApplyMaterial(material);
      cube.transform.scaling = { 100, 100, 100 };
      cube.transform.orientation = Euler { 50, 30, 50 };
      cube.UpdateTransform();
      return true;
   }

   void OnUnloadGraphics()
   {
      cube.Free(display.displaySystem);
   }

   void OnRedraw(Surface surface)
   {
      camera.Setup(clientSize.w, clientSize.h, null);
      camera.Update();

      surface.Clear(colorAndDepth);
      display.SetLight(0, light);
      display.SetCamera(surface, camera);
      display.DrawObject(cube);
      display.SetCamera(surface, null);

      surface.WriteTextf(10, 10, "Hello, WPAL & 3D GFX!");
   }

   bool OnKeyDown(Key key, unichar ch)
   {
      if(key == escape) Destroy(0);
      return true;
   }
}

Hello3D hello3D {};

Hello3D hello3D2 { caption = "Second Window!!", background = navy, anchor = { top = 100, right = 100 } };
