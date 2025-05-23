#define _Noreturn

namespace drivers;

import "RootWindow"
import "Interface"
import "Condition"

#define uint _uint
#define set _set
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <locale.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/prctl.h>

#include <android/configuration.h>
#include <android/looper.h>
#include <android/native_activity.h>
#include <android/sensor.h>
#include <android/log.h>
#include <android/window.h>

#include <jni.h>
#undef set
#undef uint

#define printf(...) ((void)__android_log_print(ANDROID_LOG_INFO, "ecere-app", __VA_ARGS__))

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "ecere-app", __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, "ecere-app", __VA_ARGS__))
#define LOGW(...) ((void)__android_log_print(ANDROID_LOG_WARN, "ecere-app", __VA_ARGS__))
#ifndef _DEBUG
#define LOGV(...)  ((void)0)
#else
#define LOGV(...)  ((void)__android_log_print(ANDROID_LOG_VERBOSE, "ecere-app", __VA_ARGS__))
#endif

// *** NATIVE APP GLUE ********
enum LooperID { main = 1, input = 2, user = 3 };
enum AppCommand : byte
{
   error = 0, inputChanged, initWindow, termWindow, windowResized, windowRedrawNeeded,
   contentRectChanged, gainedFocus, lostFocus,
   configChanged, lowMemory, start, resume, saveState, pause, stop, destroy
};

class AndroidPollSource
{
public:
   void * userData;
   LooperID id;
   virtual void any_object::process();
};

static const char * packagePath;

class AndroidAppGlue : Thread
{
   void* userData;
   virtual void onAppCmd(AppCommand cmd);
   virtual int onInputEvent(AInputEvent* event);
   virtual void main();

   ANativeActivity* activity;
   AConfiguration* config;
   void* savedState;
   uint savedStateSize;

   ALooper* looper;
   AInputQueue* inputQueue;
   ANativeWindow* window;
   ARect contentRect;
   AppCommand activityState;
   bool destroyRequested;
   char * moduleName;

private:
   Mutex mutex { };
   Condition cond { };

   int msgread, msgwrite;

   unsigned int Main()
   {
      config = AConfiguration_new();
      AConfiguration_fromAssetManager(config, activity->assetManager);

      print_cur_config();

      looper = ALooper_prepare(ALOOPER_PREPARE_ALLOW_NON_CALLBACKS);
      ALooper_addFd(looper, msgread, LooperID::main, ALOOPER_EVENT_INPUT, null, cmdPollSource);

      mutex.Wait();
      running = true;
      cond.Signal();
      mutex.Release();

      main();

      destroy();
      return 0;
   }

   void setupLocation()
   {
      JNIEnv * env = activity->env;
      JavaVM * vm = activity->vm;
      jclass cContext;
      jclass cLocationManager;
      jclass cCriteria;
      jmethodID criteriaConstID;
      jmethodID setAccuracyID;
      jfieldID lsFID;
      jfieldID fineFID;
      jstring jstr;
      jmethodID getSystemServiceID;
      jobject lm = NULL;
      jclass cActivityThread;
      jobject at;
      jmethodID currentActivityThreadID;
      jmethodID getApplicationID;
      jmethodID getBestProviderID;
      jmethodID requestLocationUpdatesID;
      jobject criteria;
      jobject context;
      int accuracyFine;

      //(*vm)->AttachCurrentThread(vm, &env, NULL);
      cActivityThread = (*env)->FindClass(env,"android/app/ActivityThread");
      cCriteria = (*env)->FindClass(env,"android/location/Criteria");
      currentActivityThreadID = (*env)->GetStaticMethodID(env, cActivityThread, "currentActivityThread", "()Landroid/app/ActivityThread;");
      at = (*env)->CallStaticObjectMethod(env, cActivityThread, currentActivityThreadID);
      getApplicationID = (*env)->GetMethodID(env, cActivityThread, "getApplication", "()Landroid/app/Application;");
      context = (*env)->CallObjectMethod(env, at, getApplicationID);
      cLocationManager = (*env)->FindClass(env, "android/location/LocationManager");
      getBestProviderID = (*env)->GetMethodID(env, cLocationManager, "getBestProvider", "(Landroid/location/Criteria;Z)Ljava/lang/String;");
      requestLocationUpdatesID = (*env)->GetMethodID(env, cLocationManager, "requestLocationUpdates", "(Ljava/lang/String;JFLandroid/location/LocationListener;)V");

      cContext = (*env)->FindClass(env, "android/content/Context");
      lsFID = (*env)->GetStaticFieldID(env, cContext, "LOCATION_SERVICE", "Ljava/lang/String;");
      jstr = (*env)->GetStaticObjectField(env, cContext, lsFID);

      criteriaConstID = (*env)->GetMethodID(env, cCriteria, "<init>", "()V");
      criteria = (*env)->NewObject(env, cCriteria, criteriaConstID);

      //locationListener = (*env)->NewObject(env, cLocationListener, locationListenerConstID);

       fineFID = (*env)->GetStaticFieldID(env, cCriteria, "ACCURACY_FINE", "I");
      //fineFID = (*env)->GetStaticFieldID(env, cCriteria, "ACCURACY_COARSE", "I");
      accuracyFine = (*env)->GetStaticIntField(env, cCriteria, fineFID);
      setAccuracyID = (*env)->GetMethodID(env, cCriteria, "setAccuracy", "(I)V");
      (*env)->CallVoidMethod(env, criteria, setAccuracyID, accuracyFine);
      context = (*env)->CallObjectMethod(env, at, getApplicationID);

      getSystemServiceID = (*env)->GetMethodID(env, cContext, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
      lm = (*env)->CallObjectMethod(env, context, getSystemServiceID, jstr);
      jstr = (*env)->CallObjectMethod(env, lm, getBestProviderID, criteria, (jboolean)0);
      if(jstr) // Note: location system service will be null if location wasn't enabled in manifest
      {
         const char *s = (*env)->GetStringUTFChars(env, jstr, 0);
         PrintLn("Requesting location from: ", s);
         (*env)->ReleaseStringUTFChars(env, jstr, s);
         (*env)->CallVoidMethod(env, lm, requestLocationUpdatesID, jstr, (jlong)1000, (jfloat)1.0f, activity->clazz);
      }

      //(*vm)->DetachCurrentThread(vm);
   }

   void destroy()
   {
      free_saved_state();
      mutex.Wait();
      if(inputQueue)
         AInputQueue_detachLooper(inputQueue);
      AConfiguration_delete(config);
      destroyed = true;
      cond.Signal();
      mutex.Release();
   }

   AndroidPollSource cmdPollSource
   {
      this, main;

      void process()
      {
         AppCommand cmd = read_cmd();
         pre_exec_cmd(cmd);
         onAppCmd(cmd);
         post_exec_cmd(cmd);
      }
   };
   AndroidPollSource inputPollSource
   {
      this, input;

      void process()
      {
         AInputEvent* event = null;
         if(AInputQueue_getEvent(inputQueue, &event) >= 0)
         {
            //int handled = 0;
            LOGV("New input event: type=%d\n", AInputEvent_getType(event));
            if(AInputQueue_preDispatchEvent(inputQueue, event))
               return;
            /*handled = */onInputEvent(event);
            //AInputQueue_finishEvent(inputQueue, event, handled);
         }
         else
            LOGE("Failure reading next input event: %s\n", strerror(errno));
      }
   };

   bool running;
   bool stateSaved;
   bool destroyed;
   AInputQueue* pendingInputQueue;
   ANativeWindow* pendingWindow;
   ARect pendingContentRect;

   void free_saved_state()
   {
      mutex.Wait();
      if(savedState)
         free(savedState);
      savedState = 0;
      savedStateSize = 0;
      mutex.Release();
   }

   AppCommand read_cmd()
   {
      AppCommand cmd;
      if(read(msgread, &cmd, sizeof(cmd)) == sizeof(cmd))
      {
         if(cmd == saveState)
            free_saved_state();
         return cmd;
      }
      else
         LOGE("No data on command pipe!");
      return error;
   }

   void print_cur_config()
   {
      char lang[2], country[2];
      AConfiguration_getLanguage(config, lang);
      AConfiguration_getCountry(config, country);

      LOGV("Config: mcc=%d mnc=%d lang=%c%c cnt=%c%c orien=%d touch=%d dens=%d "
              "keys=%d nav=%d keysHid=%d navHid=%d sdk=%d size=%d long=%d "
              "modetype=%d modenight=%d",
              AConfiguration_getMcc(config),
              AConfiguration_getMnc(config),
              lang[0], lang[1], country[0], country[1],
              AConfiguration_getOrientation(config),
              AConfiguration_getTouchscreen(config),
              AConfiguration_getDensity(config),
              AConfiguration_getKeyboard(config),
              AConfiguration_getNavigation(config),
              AConfiguration_getKeysHidden(config),
              AConfiguration_getNavHidden(config),
              AConfiguration_getSdkVersion(config),
              AConfiguration_getScreenSize(config),
              AConfiguration_getScreenLong(config),
              AConfiguration_getUiModeType(config),
              AConfiguration_getUiModeNight(config));
   }

   void pre_exec_cmd(AppCommand cmd)
   {
      //PrintLn("pre_exec_cmd: ", cmd);
      switch(cmd)
      {
         case inputChanged:
            mutex.Wait();
            if(inputQueue)
               AInputQueue_detachLooper(inputQueue);
            inputQueue = pendingInputQueue;
            if(inputQueue)
               AInputQueue_attachLooper(inputQueue, looper, LooperID::input, null, inputPollSource);
            cond.Signal();
            mutex.Release();
            break;
         case initWindow:
            mutex.Wait();
            window = pendingWindow;
            cond.Signal();
            mutex.Release();
            break;
         case termWindow:
            cond.Signal();
            break;
         case resume:
         case start:
         case pause:
         case stop:
            mutex.Wait();
            activityState = cmd;
            cond.Signal();
            mutex.Release();
            break;
         case configChanged:
            AConfiguration_fromAssetManager(config, activity->assetManager);
            print_cur_config();
            break;
         case destroy:
            destroyRequested = true;
            break;
      }
   }

   void post_exec_cmd(AppCommand cmd)
   {
      //PrintLn("post_exec_cmd: ", cmd);
      switch(cmd)
      {
         case termWindow:
            mutex.Wait();
            window = null;
            cond.Signal();
            mutex.Release();
            break;
         case saveState:
            mutex.Wait();
            stateSaved = true;
            cond.Signal();
            mutex.Release();
            break;
         case resume:
            free_saved_state();
            break;
      }
   }

   void write_cmd(AppCommand cmd)
   {
      if(write(msgwrite, &cmd, sizeof(cmd)) != sizeof(cmd))
         LOGE("Failure writing android_app cmd: %s\n", strerror(errno));
   }

   void set_input(AInputQueue* inputQueue)
   {
      mutex.Wait();
      pendingInputQueue = inputQueue;
      write_cmd(inputChanged);
      while(inputQueue != pendingInputQueue)
         cond.Wait(mutex);
      mutex.Release();
   }

   void set_window(ANativeWindow* window)
   {
      mutex.Wait();
      if(pendingWindow)
         write_cmd(termWindow);
      pendingWindow = window;
      if(window)
         write_cmd(initWindow);
      while(window != pendingWindow)
         cond.Wait(mutex);
      mutex.Release();
   }

   void set_activity_state(AppCommand cmd)
   {
      mutex.Wait();
      write_cmd(cmd);
      while(activityState != cmd)
         cond.Wait(mutex);
      mutex.Release();
   }

   void cleanup()
   {
      mutex.Wait();
      write_cmd(destroy);
      while(!destroyed)
         cond.Wait(mutex);
      mutex.Release();
      close(msgread);
      close(msgwrite);
   }

   void setSavedState(void * state, uint size)
   {
      if(savedState)
         free(savedState);
      savedState = null;
      if(state)
      {
         savedState = malloc(size);
         savedStateSize = size;
         memcpy(savedState, state, size);
      }
      else
         savedStateSize = 0;
   }

   public void Create()
   {
      int msgpipe[2];
      if(pipe(msgpipe))
         LOGE("could not create pipe: %s", strerror(errno));
      msgread = msgpipe[0];
      msgwrite = msgpipe[1];

      Thread::Create();

      // Wait for thread to start.
      mutex.Wait();
      while(!running) cond.Wait(mutex);
      mutex.Release();
   }
}

// Callbacks
static void onDestroy(ANativeActivity* activity)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("Destroy: %p\n", activity);
   app.cleanup();
   app.Wait();
   delete androidActivity;
   delete __androidCurrentModule;
   LOGI("THE END.");
}

static void onStart(ANativeActivity* activity)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("Start: %p\n", activity);
   app.set_activity_state(start);
}

static void onResume(ANativeActivity* activity)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("Resume: %p\n", activity);
   app.set_activity_state(resume);
}

static void* onSaveInstanceState(ANativeActivity* activity, size_t* outLen)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   void* savedState = null;
   LOGI("SaveInstanceState: %p\n", activity);
   app.mutex.Wait();
   app.stateSaved = false;
   app.write_cmd(saveState);
   while(!app.stateSaved)
      app.cond.Wait(app.mutex);
   if(app.savedState)
   {
      savedState = app.savedState;
      *outLen = app.savedStateSize;
      app.savedState = null;
      app.savedStateSize = 0;
   }
   app.mutex.Release();
   return savedState;
}

static void onPause(ANativeActivity* activity)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("Pause: %p\n", activity);
   app.set_activity_state(pause);
}

static void onStop(ANativeActivity* activity)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("Stop: %p\n", activity);
   app.set_activity_state(stop);
}

static void onConfigurationChanged(ANativeActivity* activity)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("ConfigurationChanged: %p\n", activity);
   app.write_cmd(configChanged);
}

static void onLowMemory(ANativeActivity* activity)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("LowMemory: %p\n", activity);
   app.write_cmd(lowMemory);
}

static void onWindowFocusChanged(ANativeActivity* activity, int focused)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("WindowFocusChanged: %p -- %d\n", activity, focused);
   app.write_cmd(focused ? gainedFocus : lostFocus);
}

static void onNativeWindowCreated(ANativeActivity* activity, ANativeWindow* window)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("NativeWindowCreated: %p -- %p\n", activity, window);
   app.set_window(window);
}

static void onNativeWindowDestroyed(ANativeActivity* activity, ANativeWindow* window)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("NativeWindowDestroyed: %p -- %p\n", activity, window);
   app.window = null;
   app.set_window(null);
}

static void onInputQueueCreated(ANativeActivity* activity, AInputQueue* queue)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("InputQueueCreated: %p -- %p\n", activity, queue);
   app.set_input(queue);
}

static void onInputQueueDestroyed(ANativeActivity* activity, AInputQueue* queue)
{
   AndroidAppGlue app = (AndroidAppGlue)activity->instance;
   LOGI("InputQueueDestroyed: %p -- %p\n", activity, queue);
   app.inputQueue = null;
   app.set_input(null);
}

default dllexport const void * Android_getJNIEnv()
{
   const void * foo = androidActivity ? androidActivity.activity->env : null;
   PrintLn("getJNIEnv returned ", (uintptr)foo);
   return foo;
}

default dllexport const void * Android_getJavaVM()
{
   return androidActivity ? androidActivity.activity->vm : null;
}

default dllexport const void * Android_getActivity()
{
   return androidActivity ? androidActivity.activity->clazz : null;
}

default dllexport void ANativeActivity_onCreate(ANativeActivity* activity, void* savedState, size_t savedStateSize)
{
   AndroidAppGlue app;
   char * moduleName;

   // Determine our package name
   JNIEnv* env=activity->env;
   jclass clazz;
   const char* str;
   jboolean isCopy;
   jmethodID methodID;
   jobject result;

   // *** Reinitialize static global variables ***
   gotInit = false;
   guiApplicationInitialized = false;
   guiApp = null;
   desktopW = 0; desktopH = 0;
   clipBoardData = null;
   __thisModule = null;
   __androidCurrentModule = null;

   prctl(PR_SET_DUMPABLE, 1);

   LOGI("Creating: %p\n", activity);

   //(*activity->vm)->AttachCurrentThread(activity->vm, &env, 0);
   clazz = (*env)->GetObjectClass(env, activity->clazz);
   methodID = (*env)->GetMethodID(env, clazz, "getPackageName", "()Ljava/lang/String;");
   result = (*env)->CallObjectMethod(env, activity->clazz, methodID);
   str = (*env)->GetStringUTFChars(env, (jstring)result, &isCopy);

   moduleName = strstr(str, "com.ecere.");
   if(moduleName) moduleName += 10;
   androidArgv[0] = moduleName;

   methodID = (*env)->GetMethodID(env, clazz, "getPackageCodePath", "()Ljava/lang/String;");
   result = (*env)->CallObjectMethod(env, activity->clazz, methodID);
   str = (*env)->GetStringUTFChars(env, (jstring)result, &isCopy);
   packagePath = str;
   // (*activity->vm)->DetachCurrentThread(activity->vm);
   LOGI("packagePath: %s\n", packagePath);

   // Create a base Application class
   __androidCurrentModule = __ecere_COM_Initialize(true, 1, androidArgv);
   // Load up Ecere
   eModule_Load(__androidCurrentModule, "ecere", publicAccess);

   /*
   if(activity->internalDataPath) PrintLn("internalDataPath is ", activity->internalDataPath);
   if(activity->externalDataPath) PrintLn("externalDataPath is ", activity->externalDataPath);
   {
      char tmp[256];
      PrintLn("cwd is ", GetWorkingDir(tmp, sizeof(tmp)));
   }
   */

   ANativeActivity_setWindowFlags(activity, AWINDOW_FLAG_FULLSCREEN|AWINDOW_FLAG_KEEP_SCREEN_ON, 0 );
   app = AndroidActivity { activity = activity, moduleName = moduleName };

   incref app;
   app.setSavedState(savedState, (uint)savedStateSize);
   activity->callbacks->onDestroy = onDestroy;
   activity->callbacks->onStart = onStart;
   activity->callbacks->onResume = onResume;
   activity->callbacks->onSaveInstanceState = onSaveInstanceState;
   activity->callbacks->onPause = onPause;
   activity->callbacks->onStop = onStop;
   activity->callbacks->onConfigurationChanged = onConfigurationChanged;
   activity->callbacks->onLowMemory = onLowMemory;
   activity->callbacks->onWindowFocusChanged = onWindowFocusChanged;
   activity->callbacks->onNativeWindowCreated = onNativeWindowCreated;
   activity->callbacks->onNativeWindowDestroyed = onNativeWindowDestroyed;
   activity->callbacks->onInputQueueCreated = onInputQueueCreated;
   activity->callbacks->onInputQueueDestroyed = onInputQueueDestroyed;
   activity->instance = app;
   app.Create();

   {
      JNIEnv * env = activity->env;
      if(env)
      {
         jclass classNativeActivity = (*env)->FindClass(env, "android/app/NativeActivity");
         jclass classWindowManager = (*env)->FindClass(env, "android/view/WindowManager");
         jclass classDisplay = (*env)->FindClass(env, "android/view/Display");
         if(classWindowManager)
         {
            jmethodID idNativeActivity_getWindowManager = (*env)->GetMethodID(env, classNativeActivity, "getWindowManager", "()Landroid/view/WindowManager;");
            jmethodID idWindowManager_getDefaultDisplay = (*env)->GetMethodID(env, classWindowManager, "getDefaultDisplay", "()Landroid/view/Display;");
            jmethodID idWindowManager_getRotation = (*env)->GetMethodID(env, classDisplay, "getRotation", "()I");
            if(idWindowManager_getRotation)
            {
               jobject windowManager = (*env)->CallObjectMethod(env, activity->clazz, idNativeActivity_getWindowManager);
               if(windowManager)
               {
                  jobject display = (*env)->CallObjectMethod(env, windowManager, idWindowManager_getDefaultDisplay);
                  if(display)
                  {
                     int rotation = (*env)->CallIntMethod(env, display, idWindowManager_getRotation);
                     ((AndroidActivity)app).defaultRotation = rotation;
                     switch(rotation)
                     {
                        case 0: PrintLn("Default rotation is ROTATION_0"); break;
                        case 1: PrintLn("Default rotation is ROTATION_90"); break;
                        case 2: PrintLn("Default rotation is ROTATION_180"); break;
                        case 3: PrintLn("Default rotation is ROTATION_270"); break;
                     }
                  }
               }
            }
         }

      }
   }

   app.setupLocation();
}

// *** END OF NATIVE APP GLUE ******

default:
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyHit;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyUp;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyDown;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyHit;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnMouseMove;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnLeftDoubleClick;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnLeftButtonDown;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnLeftButtonUp;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnMiddleDoubleClick;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnMiddleButtonDown;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnMiddleButtonUp;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnRightDoubleClick;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnRightButtonDown;
extern int __ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnRightButtonUp;
private:

static Module __androidCurrentModule;
static char * androidArgv[1];

static int desktopW, desktopH;
static char * clipBoardData;
static int mouseX, mouseY;

class AndroidInterface : Interface
{
   class_property(name) = "Android";

   // --- User Interface System ---
   bool Initialize()
   {
      setlocale(LC_ALL, "en_US.UTF-8");
      return true;
   }

   void Terminate()
   {

   }

   #define DBLCLICK_DELAY  300   // 0.3 second
   #define DBLCLICK_DELTA  1

   bool ProcessInput(bool processAll)
   {
      bool eventAvailable = false;

      if(androidActivity.ident < 0)
         androidActivity.ident = (LooperID)ALooper_pollAll(0, null, &androidActivity.events, (void**)&androidActivity.source);

      if(gotInit && androidActivity.window)
      {
         int w = ANativeWindow_getWidth(androidActivity.window);
         int h = ANativeWindow_getHeight(androidActivity.window);
         if(desktopW != w || desktopH != h)
         {
            guiApp.SetDesktopPosition(0, 0, w, h, true);
            desktopW = w;
            desktopH = h;
            guiApp.desktop.Update(null);
         }
      }

      while(androidActivity.ident >= 0)
      {
         AndroidPollSource source = androidActivity.source;

         androidActivity.source = null;
         if(source)
            source.process(source.userData);

         // If a sensor has data, process it now.
         if(androidActivity.ident == user)
         {
            if(androidActivity.accelerometerSensor || androidActivity.compassSensor || androidActivity.dofSensor)
            {
               ASensorEvent event;
               while (ASensorEventQueue_getEvents(androidActivity.sensorEventQueue, &event, 1) > 0)
               {
                  switch(event.type)
                  {
                     case ASENSOR_TYPE_ROTATION_VECTOR:
                     {
                        Matrix rm, tmp;
                        double values[3];
                        Quaternion q1, q2, q3;

                        // LOGI("raw: x=%.05f y=%.05f z=%.05f w=%.05f (%.05f)", event.vector.x, event.vector.y, event.vector.z, event.data[3], q.w);

                        getRotationMatrixFromVector(rm, event.data);

                        #define AXIS_MINUS_X 0x81
                        #define AXIS_MINUS_Y 0x82
                        #define AXIS_MINUS_Z 0x83
                        #define AXIS_X       0x01
                        #define AXIS_Y       0x02
                        #define AXIS_Z       0x03

                        switch(androidActivity.defaultRotation)
                        {
                           case 0:                                                                       break; // 0
                           case 1: remapCoordinateSystem(rm, AXIS_Y,       AXIS_MINUS_X, tmp); rm = tmp; break; // 90
                           case 2: remapCoordinateSystem(rm, AXIS_MINUS_X, AXIS_MINUS_Y, tmp); rm = tmp; break; // 180
                           case 3: remapCoordinateSystem(rm, AXIS_MINUS_Y, AXIS_X,       tmp); rm = tmp; break; // 270
                        }
                        getOrientation(rm, values);
                        compass.yaw   = Radians { values[0] };
                        compass.pitch = Radians { values[1] };
                        compass.roll  = Radians { values[2] };

                        q1 = compass;
                        q2.RotationYawPitchRoll({ 0, 90, 0 });
                        q3.Multiply(q2, q1);
                        compass = q3;
                        compass.roll = -compass.roll;

                        // PrintLn("Yaw: ", (double)compass.yaw, ", Pitch: ", (double)compass.pitch, ", Roll: ", (double)compass.roll);
                        break;
                     }
                     case ASENSOR_TYPE_ACCELEROMETER:
                        // LOGI("accelerometer: x=%.02f y=%.02f z=%.02f", event.acceleration.x, event.acceleration.y, event.acceleration.z);
                        break;
                     case ASENSOR_TYPE_POSE_6DOF:
                     {
                        Quaternion q { event.data[0], event.data[1], event.data[2], event.data[3] };
                        Vector3D t { event.data[4], event.data[5], event.data[6] };
                        Euler e;

                        e.FromQuaternion(q, yxz);

                        LOGI("orientation: yaw=%.02f pitch=%.02f roll=%.02f", (double)e.yaw, (double)e.pitch, (double)e.roll);
                        LOGI("translation: x=%.02f y=%.02f z=%.02f", (double)t.x, (double)t.y, (double)t.z);
                        LOGI("---");

                        /*
                        values[0]: x*sin(θ/2)
                        values[1]: y*sin(θ/2)
                        values[2]: z*sin(θ/2)
                        values[3]: cos(θ/2)
                        values[4]: Translation along x axis from an arbitrary origin.
                        values[5]: Translation along y axis from an arbitrary origin.
                        values[6]: Translation along z axis from an arbitrary origin.
                        values[7]: Delta quaternion rotation x*sin(θ/2)
                        values[8]: Delta quaternion rotation y*sin(θ/2)
                        values[9]: Delta quaternion rotation z*sin(θ/2)
                        values[10]: Delta quaternion rotation cos(θ/2)
                        values[11]: Delta translation along x axis.
                        values[12]: Delta translation along y axis.
                        values[13]: Delta translation along z axis.
                        values[14]: Sequence number
                        */
                        break;
                     }
                  }
               }
            }
         }

         eventAvailable = true;
         if(androidActivity.destroyRequested)
         {
            guiApp.desktop.Destroy(0);
            eventAvailable = true;
            androidActivity.ident = (LooperID)-1;
         }
         else if(processAll)
            androidActivity.ident = (LooperID)ALooper_pollAll(0, null, &androidActivity.events, (void**)&androidActivity.source);
         else
            androidActivity.ident = (LooperID)-1;
      }
      return eventAvailable;
   }

   void Wait()
   {
      androidActivity.ident = (LooperID)ALooper_pollAll((int)(1000/18.2f), null, &androidActivity.events, (void**)&androidActivity.source);
      // guiApp.WaitEvent();
   }

   void Lock(Window window)
   {

   }

   void Unlock(Window window)
   {

   }

   const char ** GraphicsDrivers(int * numDrivers)
   {
      static const char *graphicsDrivers[] = { "OpenGL" };
      *numDrivers = sizeof(graphicsDrivers) / sizeof(char *);
      return (const char **)graphicsDrivers;
   }

   void GetCurrentMode(bool * fullScreen, int * resolution, int * colorDepth, int * refreshRate)
   {
      *fullScreen = true;
   }

   void EnsureFullScreen(bool *fullScreen)
   {
      *fullScreen = true;
   }

   bool ScreenMode(bool fullScreen, int resolution, int colorDepth, int refreshRate, bool * textMode)
   {
      bool result = true;

      return result;
   }

   // --- Window Creation ---
   void * CreateRootWindow(Window window)
   {
      return androidActivity.window;
   }

   void DestroyRootWindow(Window window)
   {

   }

   // -- Window manipulation ---

   void SetRootWindowCaption(Window window, const char * name)
   {

   }

   void PositionRootWindow(Window window, int x, int y, int w, int h, bool move, bool resize)
   {

   }

   void OrderRootWindow(Window window, bool topMost)
   {

   }

   void SetRootWindowColor(Window window)
   {

   }

   void OffsetWindow(Window window, int * x, int * y)
   {

   }

   void UpdateRootWindow(Window window)
   {
      if(!window.parent || !window.parent.display)
      {
         if(window.visible)
         {
            Box box = window.box;
            box.left -= window.clientStart.x;
            box.top -= window.clientStart.y;
            box.right -= window.clientStart.x;
            box.bottom -= window.clientStart.y;
            // Logf("Update root window %s\n", window.name);
            window.Update(null);
            box.left   += window.clientStart.x;
            box.top    += window.clientStart.y;
            box.right  += window.clientStart.x;
            box.bottom += window.clientStart.y;
            window.UpdateDirty(box);
         }
      }
   }


   void SetRootWindowState(Window window, WindowState state, bool visible)
   {
   }

   void FlashRootWindow(Window window)
   {

   }

   void ActivateRootWindow(Window window)
   {

   }

   // --- Mouse-based window movement ---

   void StartMoving(Window window, int x, int y, bool fromKeyBoard)
   {

   }

   void StopMoving(Window window)
   {

   }

   // -- Mouse manipulation ---

   void GetMousePosition(int *x, int *y)
   {
      *x = mouseX;
      *y = mouseY;
   }

   void SetMousePosition(int x, int y)
   {
      mouseX = x;
      mouseY = y;
   }

   void SetMouseRange(Window window, Box box)
   {
   }

   void SetMouseCapture(Window window)
   {
   }

   // -- Mouse cursor ---

   void SetMouseCursor(Window window, int cursor)
   {
      if(cursor == -1)
      {

      }
   }

   // --- Caret ---

   void SetCaret(int x, int y, int size)
   {
      Window caretOwner = guiApp.caretOwner;
      Window window = caretOwner ? caretOwner.rootWindow : null;
      if(window && window.windowData)
      {
      }
   }

   void ClearClipboard()
   {
      if(clipBoardData)
      {
         delete clipBoardData;
      }
   }

   bool AllocateClipboard(ClipBoard clipBoard, uint size)
   {
      bool result = false;
      if((clipBoard.text = new0 byte[size]))
         result = true;
      return result;
   }

   bool SaveClipboard(ClipBoard clipBoard)
   {
      bool result = false;
      if(clipBoard.text)
      {
         if(clipBoardData)
            delete clipBoardData;

         clipBoardData = clipBoard.text;
         clipBoard.text = null;
         result = true;
      }
      return result;
   }

   bool LoadClipboard(ClipBoard clipBoard)
   {
      bool result = false;

      // The data is inside this client...
      if(clipBoardData)
      {
         clipBoard.text = new char[strlen(clipBoardData)+1];
         strcpy(clipBoard.text, clipBoardData);
         result = true;
      }
      // The data is with another client...
      else
      {
      }
      return result;
   }

   void UnloadClipboard(ClipBoard clipBoard)
   {
      delete clipBoard.text;
   }

   // --- State based input ---

   bool AcquireInput(Window window, bool state)
   {
      return false;
   }

   bool GetMouseState(MouseButtons * buttons, int * x, int * y)
   {
      bool result = false;
      if(x) *x = 0;
      if(y) *y = 0;
      return result;
   }

   bool GetJoystickState(int device, Joystick joystick)
   {
      bool result = false;
      return result;
   }

   bool GetKeyState(Key key)
   {
      bool keyState = false;
      return keyState;
   }

   void SetTimerResolution(uint hertz)
   {
      // timerDelay = hertz ? (1000000 / hertz) : MAXINT;
   }

   bool SetIcon(Window window, BitmapResource resource)
   {
      if(resource)
      {
         /*Bitmap bitmap { };
         if(bitmap.Load(resource.fileName, null, null))
         {
         }
         delete bitmap;*/
      }
      return true;
   }
}

struct SavedState
{
    float angle;
    int x;
    int y;
};

static AndroidActivity androidActivity;

default const char * AndroidInterface_GetLibLocation(Application a)
{
   static char loc[MAX_LOCATION] = "", mod[MAX_LOCATION];
   bool found = false;
#if defined(__LP64__)
   static const char * arch = "arm64";
#else
   static const char * arch = "armeabi";
#endif
   int i;
   bool useArch = true;

   while(!found)
   {
      StripLastDirectory(packagePath, loc);
      strcatf(loc, "/lib/%s/lib", useArch ? arch : "");
      sprintf(mod, "%s%s.so", loc, a.argv[0]);
      found = FileExists(mod).isFile;
      if(!found)
      {
         bool useApp = true;
         while(!found)
         {
            for(i = 0; !found && i < 10; i++)
            {
               if(i)
                  sprintf(loc, "/data/%s/com.ecere.%s-%d/lib/%s/lib", useApp ? "app" : "data", a.argv[0], i, useArch ? arch : "");
               else
                  sprintf(loc, "/data/%s/com.ecere.%s/lib/%s/lib",    useApp ? "app" : "data", a.argv[0], useArch ? arch : "");
               sprintf(mod, "%s%s.so", loc, a.argv[0]);
               found = FileExists(mod).isFile;
            }
            if(useApp)
               useApp = false;
            else
               break;
         }
      }
      if(useArch)
         useArch = false;
      else
         break;
   }
   return loc;
}

static bool gotInit;

default float AMotionEvent_getAxisValue(const AInputEvent* motion_event,
        int32_t axis, size_t pointer_index);


static define AMETA_META_ON       = 0x00010000;
static define AMETA_META_LEFT_ON  = 0x00020000;
static define AMETA_META_RIGHT_ON = 0x00040000;

static Key keyCodeTable[] =
{
    0, //AKEYCODE_UNKNOWN         = 0,
    0, //AKEYCODE_SOFT_LEFT       = 1,
    0, //AKEYCODE_SOFT_RIGHT      = 2,
    0, //AKEYCODE_HOME            = 3,
    0, //AKEYCODE_BACK            = 4,
    0, //AKEYCODE_CALL            = 5,
    0, //AKEYCODE_ENDCALL         = 6,
    k0, //AKEYCODE_0               = 7,
    k1, //AKEYCODE_1               = 8,
    k2, //AKEYCODE_2               = 9,
    k3, //AKEYCODE_3               = 10,
    k4, //AKEYCODE_4               = 11,
    k5, //AKEYCODE_5               = 12,
    k6, //AKEYCODE_6               = 13,
    k7, //AKEYCODE_7               = 14,
    k8, //AKEYCODE_8               = 15,
    k9, //AKEYCODE_9               = 16,
    keyPadStar, //AKEYCODE_STAR            = 17,
    Key { k3, shift = true }, //AKEYCODE_POUND           = 18,
    up, //AKEYCODE_DPAD_UP         = 19,
    down, //AKEYCODE_DPAD_DOWN       = 20,
    left, //AKEYCODE_DPAD_LEFT       = 21,
    right, //AKEYCODE_DPAD_RIGHT      = 22,
    keyPad5, //AKEYCODE_DPAD_CENTER     = 23,
    0, //AKEYCODE_VOLUME_UP       = 24,
    0, //AKEYCODE_VOLUME_DOWN     = 25,
    0, //AKEYCODE_POWER           = 26,
    0, //AKEYCODE_CAMERA          = 27,
    0, //AKEYCODE_CLEAR           = 28,
    a, //AKEYCODE_A               = 29,
    b, //AKEYCODE_B               = 30,
    c, //AKEYCODE_C               = 31,
    d, //AKEYCODE_D               = 32,
    e, //AKEYCODE_E               = 33,
    f, //AKEYCODE_F               = 34,
    g, //AKEYCODE_G               = 35,
    h, //AKEYCODE_H               = 36,
    i, //AKEYCODE_I               = 37,
    j, //AKEYCODE_J               = 38,
    k, //AKEYCODE_K               = 39,
    l, //AKEYCODE_L               = 40,
    m, //AKEYCODE_M               = 41,
    n, //AKEYCODE_N               = 42,
    o, //AKEYCODE_O               = 43,
    p, //AKEYCODE_P               = 44,
    q, //AKEYCODE_Q               = 45,
    r, //AKEYCODE_R               = 46,
    s, //AKEYCODE_S               = 47,
    t, //AKEYCODE_T               = 48,
    u, //AKEYCODE_U               = 49,
    v, //AKEYCODE_V               = 50,
    w, //AKEYCODE_W               = 51,
    x, //AKEYCODE_X               = 52,
    y, //AKEYCODE_Y               = 53,
    z, //AKEYCODE_Z               = 54,
    comma, //AKEYCODE_COMMA           = 55,
    period, //AKEYCODE_PERIOD          = 56,
    leftAlt, //AKEYCODE_ALT_LEFT        = 57,
    rightAlt, //AKEYCODE_ALT_RIGHT       = 58,
    leftShift, //AKEYCODE_SHIFT_LEFT      = 59,
    rightShift, //AKEYCODE_SHIFT_RIGHT     = 60,
    tab, //AKEYCODE_TAB             = 61,
    space, //AKEYCODE_SPACE           = 62,
    0, //AKEYCODE_SYM             = 63,
    0, //AKEYCODE_EXPLORER        = 64,
    0, //AKEYCODE_ENVELOPE        = 65,
    enter, //AKEYCODE_ENTER           = 66,
    backSpace, //AKEYCODE_DEL             = 67,
    backQuote, //AKEYCODE_GRAVE           = 68,
    minus, //AKEYCODE_MINUS           = 69,
    plus, //AKEYCODE_EQUALS          = 70,
    leftBracket, //AKEYCODE_LEFT_BRACKET    = 71,
    rightBracket, //AKEYCODE_RIGHT_BRACKET   = 72,
    backSlash, //AKEYCODE_BACKSLASH       = 73,
    semicolon, //AKEYCODE_SEMICOLON       = 74,
    quote, //AKEYCODE_APOSTROPHE      = 75,
    slash, //AKEYCODE_SLASH           = 76,
    Key { k2, shift = true }, //AKEYCODE_AT              = 77,
    0, //AKEYCODE_NUM             = 78,      // Interpreted as an Alt
    0, //AKEYCODE_HEADSETHOOK     = 79,
    0, //AKEYCODE_FOCUS           = 80,   // *Camera* focus
    keyPadPlus, //AKEYCODE_PLUS            = 81,
    0, //AKEYCODE_MENU            = 82,
    0, //AKEYCODE_NOTIFICATION    = 83,
    0, //AKEYCODE_SEARCH          = 84,
    0, //AKEYCODE_MEDIA_PLAY_PAUSE= 85,
    0, //AKEYCODE_MEDIA_STOP      = 86,
    0, //AKEYCODE_MEDIA_NEXT      = 87,
    0, //AKEYCODE_MEDIA_PREVIOUS  = 88,
    0, //AKEYCODE_MEDIA_REWIND    = 89,
    0, //AKEYCODE_MEDIA_FAST_FORWARD = 90,
    0, //AKEYCODE_MUTE            = 91,
    0, //AKEYCODE_PAGE_UP         = 92,
    0, //AKEYCODE_PAGE_DOWN       = 93,
    0, //AKEYCODE_PICTSYMBOLS     = 94,
    0, //AKEYCODE_SWITCH_CHARSET  = 95,
    0, //AKEYCODE_BUTTON_A        = 96,
    0, //AKEYCODE_BUTTON_B        = 97,
    0, //AKEYCODE_BUTTON_C        = 98,
    0, //AKEYCODE_BUTTON_X        = 99,
    0, //AKEYCODE_BUTTON_Y        = 100,
    0, //AKEYCODE_BUTTON_Z        = 101,
    0, //AKEYCODE_BUTTON_L1       = 102,
    0, //AKEYCODE_BUTTON_R1       = 103,
    0, //AKEYCODE_BUTTON_L2       = 104,
    0, //AKEYCODE_BUTTON_R2       = 105,
    0, //AKEYCODE_BUTTON_THUMBL   = 106,
    0, //AKEYCODE_BUTTON_THUMBR   = 107,
    0, //AKEYCODE_BUTTON_START    = 108,
    0, //AKEYCODE_BUTTON_SELECT   = 109,
    0, //AKEYCODE_BUTTON_MODE     = 110,
    escape, //AKEYCODE_BUTTON_ESCAPE = 111,
    del, //AKEYCODE_BUTTON_ESCAPE    = 112,
    leftControl, // = 113
    rightControl, // = 114
    capsLock, // = 115
    scrollLock, // = 116
    0, // = 117      KEYCODE_META_LEFT
    0, // = 118      KEYCODE_META_RIGHT
    0, // = 119      KEYCODE_FUNCTION
    printScreen, // = 120      KEYCODE_SYSRQ
    pauseBreak, // = 121
    home, // = 122
    end, // = 123
    insert // = 124
};

// Why don't we have this in the NDK :(
// default int32_t AKeyEvent_getUnichar(const AInputEvent* key_event);

static Array<TouchPointerInfo> buildPointerInfo(AInputEvent * event)
{
   uint count = (uint)AMotionEvent_getPointerCount(event);
   Array<TouchPointerInfo> infos = null;
   if(count)
   {
      int i;
      infos = { size = count };
      for(i = 0; i < count; i++)
      {
         infos[i].point = { (int)AMotionEvent_getX(event, i), (int)AMotionEvent_getY(event, i) };
         infos[i].id = (int)AMotionEvent_getPointerId(event, i);
         infos[i].pressure = AMotionEvent_getPressure(event, i);
         infos[i].size = AMotionEvent_getSize(event, i);
      }
   }
   return infos;
}

class AndroidActivity : AndroidAppGlue
{
   AndroidPollSource source;
   int events;
   LooperID ident;

   ASensorManager* sensorManager;
   ASensorEventQueue* sensorEventQueue;

   const ASensor* accelerometerSensor;
   const ASensor* compassSensor;
   const ASensor* dofSensor;

   SavedState state;

   int defaultRotation;

   int onInputEvent(AInputEvent* event)
   {
      static Time lastTime = 0;
      Window window = guiApp.desktop;
      uint type = AInputEvent_getType(event);
      if(type == AINPUT_EVENT_TYPE_MOTION)
      {
         uint actionAndIndex = AMotionEvent_getAction(event);
         //uint source = AInputEvent_getSource(event);
         uint action = actionAndIndex & AMOTION_EVENT_ACTION_MASK;
         //uint index  = (actionAndIndex & AMOTION_EVENT_ACTION_POINTER_INDEX_MASK) >> AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT;
         //uint flags = AMotionEvent_getFlags(event);
         uint meta = AMotionEvent_getMetaState(event);
         uint edge = AMotionEvent_getEdgeFlags(event);
         //int64 downTime = AMotionEvent_getDownTime(event);     // nanotime
         //int64 eventTime = AMotionEvent_getDownTime(event);
         //float axis;
         Modifiers keyFlags = 0;
         uint count = (uint)AMotionEvent_getPointerCount(event);
         int x = count ? (int)AMotionEvent_getX(event, 0) : 0;
         int y = count ? (int)AMotionEvent_getY(event, 0) : 0;
         bool shift = (meta & AMETA_SHIFT_ON) ? true : false;
         bool alt = (meta & AMETA_ALT_ON) ? true : false;
         //bool sym = (meta & AMETA_SYM_ON) ? true : false;

         keyFlags.shift = shift;
         keyFlags.alt = alt;

         //PrintLn("Got a motion input event: ", action);
         /*
         if(action == 8) //AMOTION_EVENT_ACTION_SCROLL)
            axis = AMotionEvent_getAxisValue(event, 9, index); //AMOTION_EVENT_AXIS_VSCROLL);
         */

         AInputQueue_finishEvent(inputQueue, event, 1);
         switch(action)
         {
            /*
            case 8: //AMOTION_EVENT_ACTION_SCROLL:
               window.KeyMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyHit, (axis < 0) ? wheelUp : wheelDown, 0);
               break;
               */
            case AMOTION_EVENT_ACTION_DOWN:
            {
               Time time = GetTime();
               bool result = true;
               if(Abs(x - mouseX) < 40 && Abs(y - mouseY) < 40 && time - lastTime < 0.3)
                  if(!window.MouseMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnLeftDoubleClick, x, y, &keyFlags, false, true))
                     result = false;
               lastTime = time;
               mouseX = x, mouseY = y;
               if(result)
                  // TOCHECK: Should we do result = here?
                  window.MouseMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnLeftButtonDown, x, y, &keyFlags, false, true);
               if(result)
               {
                  Array<TouchPointerInfo> infos = buildPointerInfo(event);
                  window.MultiTouchMessage(down, infos, &keyFlags, false, true);
                  delete infos;
               }
               break;
            }
            case AMOTION_EVENT_ACTION_UP:
               mouseX = x, mouseY = y;
               if(window.MouseMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnLeftButtonUp, x, y, &keyFlags, false, true))
               {
                  Array<TouchPointerInfo> infos = buildPointerInfo(event);
                  window.MultiTouchMessage(up, infos, &keyFlags, false, true);
                  delete infos;
               }
               break;
            case AMOTION_EVENT_ACTION_MOVE:
               mouseX = x, mouseY = y;
               if(window.MouseMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnMouseMove, x, y, &keyFlags, false, true))
               {
                  Array<TouchPointerInfo> infos = buildPointerInfo(event);
                  window.MultiTouchMessage(move, infos, &keyFlags, false, true);
                  delete infos;
               }
               break;
            case AMOTION_EVENT_ACTION_CANCEL: break;
            case AMOTION_EVENT_ACTION_OUTSIDE: break;
            case AMOTION_EVENT_ACTION_POINTER_DOWN:
            {
               Array<TouchPointerInfo> infos = buildPointerInfo(event);
               window.MultiTouchMessage(pointerDown, infos, &keyFlags, false, true);
               delete infos;
               break;
            }
            case AMOTION_EVENT_ACTION_POINTER_UP:
            {
               Array<TouchPointerInfo> infos = buildPointerInfo(event);
               window.MultiTouchMessage(pointerUp, infos, &keyFlags, false, true);
               delete infos;
               break;
            }
         }
         return 1;
      }
      else if(type == AINPUT_EVENT_TYPE_KEY)
      {
         uint action = AKeyEvent_getAction(event);
         //uint flags = AKeyEvent_getFlags(event);
         uint keyCode = AKeyEvent_getKeyCode(event);
         uint meta = AKeyEvent_getMetaState(event);
         Key key = keyCodeTable[keyCode];
         bool shift = (meta & AMETA_SHIFT_ON) ? true : false;
         bool alt = (meta & AMETA_ALT_ON || meta & AMETA_ALT_LEFT_ON || meta & AMETA_ALT_RIGHT_ON) ? true : false;
         //bool metaMeta = (meta & AMETA_META_ON || meta & AMETA_META_LEFT_ON || meta & AMETA_META_RIGHT_ON) ? true : false;
         //bool sym = (meta & AMETA_SYM_ON) ? true : false;
         //unichar ch = AKeyEvent_getUnichar(event);
         unichar ch = 0;

         key.shift = shift;
         key.alt = alt;

         AInputQueue_finishEvent(inputQueue, event, 1);

         // PrintLn("Got a key: action = ", action, ", flags = ", flags, ", keyCode = ", keyCode, ", meta = ", meta, ": key = ", (int)key);

         if(key)
         {
            if(action == AKEY_EVENT_ACTION_DOWN || action == AKEY_EVENT_ACTION_MULTIPLE)
            {
               /*if(key == wheelDown || key == wheelUp)
                  window.KeyMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyHit, key, ch);
               else*/
               {
                  char c = Interface::TranslateKey(key.code, shift);
                  if(c > 0) ch = c;
                  window.KeyMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyDown, key, ch);
               }
            }
            else if(action == AKEY_EVENT_ACTION_UP)
               window.KeyMessage(__ecereVMethodID___ecereNameSpace__ecere__gui__Window_OnKeyUp, key, ch);
         }
         return 1;
      }
      else
         AInputQueue_finishEvent(inputQueue, event, 0);
      return 0;
   }

   void onAppCmd(AppCommand cmd)
   {
      switch(cmd)
      {
         case saveState:
            setSavedState(&state, sizeof(state));
            break;
         case initWindow:
            if(window)
            {
               int w, h;
               gotInit = true;
               ANativeWindow_setBuffersGeometry(window, 0, 0, 0); //format);
               w = ANativeWindow_getWidth(window);
               h = ANativeWindow_getHeight(window);
               guiApp.Initialize(false);
               guiApp.desktop.windowHandle = window;
               guiApp.interfaceDriver = null;
               guiApp.SwitchMode(true, null, 0, 0, 0, null, false);

               if(desktopW != w || desktopH != h)
               {
                  guiApp.SetDesktopPosition(0, 0, w, h, true);
                  desktopW = w;
                  desktopH = h;
               }
               guiApp.desktop.Update(null);
            }
            break;
         case termWindow:
            guiApp.desktop.UnloadGraphics(false);
            break;
         case gainedFocus:
            guiApp.desktop.Update(null);
            guiApp.SetAppFocus(true);

            if(accelerometerSensor)
            {
               ASensorEventQueue_enableSensor(sensorEventQueue, accelerometerSensor);
               ASensorEventQueue_setEventRate(sensorEventQueue, accelerometerSensor, (1000L/60)*1000);
            }
            if(compassSensor)
            {
               ASensorEventQueue_enableSensor(sensorEventQueue, compassSensor);
               ASensorEventQueue_setEventRate(sensorEventQueue, compassSensor, (1000L/60)*1000);
            }
            break;
         case lostFocus:

            if(accelerometerSensor)
               ASensorEventQueue_disableSensor(sensorEventQueue, accelerometerSensor);

            if(compassSensor)
               ASensorEventQueue_disableSensor(sensorEventQueue, compassSensor);

            guiApp.SetAppFocus(false);
            guiApp.desktop.Update(null);
            break;
         case configChanged:
            if(window)
               guiApp.desktop.UpdateDisplay();
            break;
      }
   }

   void main()
   {
      androidActivity = this;
      // Let's have fun with sensors when we have an actual device to play with
      sensorManager = ASensorManager_getInstance();
      sensorEventQueue = ASensorManager_createEventQueue(sensorManager, looper, LooperID::user, null, null);

      // accelerometerSensor = ASensorManager_getDefaultSensor(sensorManager, ASENSOR_TYPE_ACCELEROMETER);
      compassSensor       = ASensorManager_getDefaultSensor(sensorManager, ASENSOR_TYPE_ROTATION_VECTOR);
      /*
      dofSensor           = ASensorManager_getDefaultSensor(sensorManager, ASENSOR_TYPE_POSE_6DOF);
      if(!dofSensor)
         PrintLn("error obtaining ASENSOR_TYPE_POSE_6DOF");
      */

      if(savedState)
         state = *(SavedState*)savedState;

      {
         Module app;

         // Evolve the Application class into a GuiApplication
         eInstance_Evolve((Instance *)&__androidCurrentModule, class(GuiApplication));

         // Wait for the initWindow command:
         guiApp.interfaceDriver = class(AndroidInterface);
         while(!gotInit)
         {
            // Can't call the GuiApplication here, because GuiApplication::Initialize() has not been called yet
            guiApp.interfaceDriver.Wait();
            guiApp.interfaceDriver.ProcessInput(true);
         }

         // Invoke __ecereDll_Load() in lib[our package name].so
         app = eModule_Load(__androidCurrentModule, moduleName, publicAccess);
         if(app)
         {
            Class c;
            // Find out if any GuiApplication class was defined in our module
            for(c = app.classes.first; c && !eClass_IsDerived(c, class(GuiApplication)); c = c.next);
            if(!c) c = class(GuiApplication);

            guiApp.lockMutex.Release();   // TOCHECK: Seems the evolve is losing our mutex lock here ?

            // Evolve the Application into it
            eInstance_Evolve((Instance *)&__androidCurrentModule, c);
            guiApp = (GuiApplication)__androidCurrentModule;

            {
               const String skin = guiApp.skin;
               *&guiApp.currentSkin = null;
               guiApp.SelectSkin(skin);
            }

            guiApp.lockMutex.Wait();

            // Call Main()
            ((void (*)(void *))(void *)__androidCurrentModule._vTbl[12])(__androidCurrentModule);
         }

         if(!destroyRequested)
            ANativeActivity_finish(activity);
         while(!destroyRequested)
         {
            guiApp.interfaceDriver.Wait();
            guiApp.interfaceDriver.ProcessInput(true);
         }
      }
   }
}

static void getRotationMatrixFromVector(Matrix R, const float * rotationVector)
{
   double q0;
   double q1 = rotationVector[0];
   double q2 = rotationVector[1];
   double q3 = rotationVector[2];
   // if(0) q0 = rotationVector[3]; else
   {
      q0 = 1 - q1 * q1 - q2 * q2 - q3 * q3;
      q0 = (q0 > 0) ? sqrt(q0) : 0;
   }
   double sq_q1 = 2 * q1 * q1;
   double sq_q2 = 2 * q2 * q2;
   double sq_q3 = 2 * q3 * q3;
   double q1_q2 = 2 * q1 * q2;
   double q3_q0 = 2 * q3 * q0;
   double q1_q3 = 2 * q1 * q3;
   double q2_q0 = 2 * q2 * q0;
   double q2_q3 = 2 * q2 * q3;
   double q1_q0 = 2 * q1 * q0;

   R.array[0] = 1 - sq_q2 - sq_q3;
   R.array[1] = q1_q2 - q3_q0;
   R.array[2] = q1_q3 + q2_q0;
   R.array[3] = 0.0f;
   R.array[4] = q1_q2 + q3_q0;
   R.array[5] = 1 - sq_q1 - sq_q3;
   R.array[6] = q2_q3 - q1_q0;
   R.array[7] = 0.0f;
   R.array[8] = q1_q3 - q2_q0;
   R.array[9] = q2_q3 + q1_q0;
   R.array[10] = 1 - sq_q1 - sq_q2;
   R.array[11] = 0.0;
   R.array[12] = R.array[13] = R.array[14] = 0.0;
   R.array[15] = 1.0;
}

static void getOrientation(const Matrix R, double * values)
{
   values[0] = atan2(R.array[1], R.array[5]);
   values[1] = asin(-R.array[9]);
   values[2] = atan2(-R.array[8], R.array[10]);
}

static void remapCoordinateSystem(const Matrix inR, int X, int Y, Matrix outR)
{
   int Z = X ^ Y;
   int x = (X & 0x3) - 1;
   int y = (Y & 0x3) - 1;
   int z = (Z & 0x3) - 1;
   int axis_y = (z + 1) % 3;
   int axis_z = (z + 2) % 3;
   bool sx, sy, sz;
   int j;

   if(((x ^ axis_y) | (y ^ axis_z)) != 0)
      Z ^= 0x80;
   sx = (X >= 0x80);
   sy = (Y >= 0x80);
   sz = (Z >= 0x80);

   for(j = 0; j < 3; j++)
   {
      int offset = j * 4, i;
      for(i = 0; i < 3; i++)
      {
         if(x == i) outR.array[offset + i] = sx ? -inR.array[offset + 0] : inR.array[offset + 0];
         if(y == i) outR.array[offset + i] = sy ? -inR.array[offset + 1] : inR.array[offset + 1];
         if(z == i) outR.array[offset + i] = sz ? -inR.array[offset + 2] : inR.array[offset + 2];
      }
   }
   outR.array[3] = outR.array[7] = outR.array[11] = outR.array[12] = outR.array[13] = outR.array[14] = 0;
   outR.array[15] = 1;
}
