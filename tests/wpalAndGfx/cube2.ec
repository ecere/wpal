import "wpalAndGfx"

class CubeApp : WPALGFXApp
{
   timerResolution = 60;

   bool Cycle(bool idle)
   {
      test3D.UpdateCube();
      test3D2.UpdateCube();
      return true;
   }
};

class Test3D : GfxWindow
{
   Camera camera
   {
      fixed,
      position = { 0, 0, -200 },
      orientation = Euler { 0, 0, 0 },
      fov = 53;
   };

   Light light
   {
      //diffuse = white;
      specular = white;
      orientation = Euler { pitch = 10, yaw = 30 };
   };

   Light light2
   {
      diffuse = white;
      //specular = white;
      orientation = Euler { pitch = 20, yaw = -30 };
   };

   property const String image
   {
      set { texture.fileName = value; }
   }

   BitmapResource texture { ":knot.png" };
   Material material { diffuse = white, ambient = blue, /*specular = red, */power = 8, opacity = 1.0f, flags = { translucent = true, doubleSided = true } };
   Cube cube { };
   Euler spin { };

   Time lastTime;

   bool UpdateCube()
   {
      Time time = GetTime(), diffTime = lastTime ? (time - lastTime) : 0;
      if(spin.yaw || spin.pitch)
      {
         int signYaw = 1, signPitch = 1;
         Radians yaw = spin.yaw, pitch = spin.pitch;
         Quaternion orientation = cube.transform.orientation;
         Euler tSpin { yaw * (double)diffTime, pitch * (double)diffTime, 0 };
         Quaternion thisSpin = tSpin, temp;

         if(yaw < 0) { yaw = -yaw; signYaw = -1; }
         if(pitch < 0) { pitch = -pitch; signPitch = -1; }
         yaw   -= (double)diffTime / 3 * yaw;
         pitch -= (double)diffTime / 3 * pitch;
         if(yaw < 0.0001) yaw = 0;
         if(pitch < 0.0001) pitch = 0;

         spin.yaw = yaw * signYaw;
         spin.pitch = pitch * signPitch;

         temp.Multiply(orientation, thisSpin);
         orientation.Normalize(temp);

         cube.transform.orientation = orientation;
         cube.UpdateTransform();
         Update(null);
      }
      lastTime = time;
      return true;
   }

   bool OnLoadGraphics()
   {
      display.ambient = ColorRGB { 0.7f, 0.7f, 0.7f };

      texture.manager = resManager;
      material.baseMap = texture.bitmap;
      cube.Create(display.displaySystem);
      cube.mesh.ApplyMaterial(material);
      cube.mesh.ApplyTranslucency(cube);
      cube.transform.scaling = { 100, 100, 100 };
      cube.transform.orientation = Euler { pitch = 20, yaw = -30 };
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
      surface.Clear(colorAndDepth);
      camera.Update();
      display.SetLight(0, light);
      display.SetLight(1, light2);
      display.SetCamera(surface, camera);
      display.fogDensity = 0;
      display.DrawObject(cube);
      display.SetCamera(surface, null);

      surface.WriteTextf(10, 10, "Hello, WPAL & 3D GFX!");
   }

   Point startClick;
   bool moving;
   Time clickTime;

   bool OnLeftButtonDown(int x, int y, Modifiers mods)
   {
      clickTime = GetTime();
      Capture();
      startClick = { x, y };
      moving = true;
      return true;
   }

   bool OnLeftButtonUp(int x, int y, Modifiers mods)
   {
      if(moving)
      {
         ReleaseCapture();
         moving = false;
      }
      return true;
   }

   bool OnMouseMove(int x, int y, Modifiers mods)
   {
      if(moving)
      {
         Time time = GetTime(), diffTime = Max(time - clickTime, 0.01);
         spin.yaw   += Degrees { (x - startClick.x) / (25.0 * (double)diffTime) };
         spin.pitch += Degrees { (startClick.y - y) / (25.0 * (double)diffTime) };
         startClick = { x, y };
         clickTime = time;
      }
      return true;
   }

   bool OnKeyHit(Key key, unichar ch)
   {
      if(key == wheelDown || key == wheelUp)
      {
         if(key == wheelDown)
            camera.position.z *= 1.1;
         else if(key == wheelUp)
            camera.position.z /= 1.1;
      }
      Update(null);
      return true;
   }

   bool OnKeyDown(Key key, unichar ch)
   {
      if(key == escape) Destroy(0);
      return true;
   }
}

Test3D test3D {image = ":fractal3.jpg" };

Test3D test3D2 { caption = "Second Window!!", background = navy, anchor = { top = 100, right = 100 } };
