#ifdef EC_STATIC
public import static "ecrt"
#else
public import "ecrt"
#endif

import "RootWindow"

public struct AnchorValue
{
   AnchorValueType type;

   union
   {
      int distance;
      float percent;
   };
   property MinMaxValue
   {
      set { distance = value; type = offset; }
      get { return distance; }
   }
   property int
   {
      set { distance = value; type = offset; }
      get { return distance; }
   }
   property double
   {
      set { percent = (float) value; type = relative; }
      get { return (double) percent; }
   }

   const char * OnGetString(char * stringOutput, void * fieldData, ObjectNotationType * onType)
   {
      if(type == offset)
      {
         sprintf(stringOutput, "%d", distance);
      }
      else if(type == relative)
      {
         int c;
         int last = 0;
         sprintf(stringOutput, "%f", percent);
         c = strlen(stringOutput)-1;
         for( ; c >= 0; c--)
         {
            if(stringOutput[c] != '0')
               last = Max(last, c);
            if(stringOutput[c] == '.')
            {
               if(last == c)
               {
                  stringOutput[c+1] = '0';
                  stringOutput[c+2] = 0;
               }
               else
                  stringOutput[last+1] = 0;
               break;
            }
         }
      }
      if(onType) *onType = none;   // TODO: Better document how OnGetString can modify this...
      return stringOutput;
   }

   bool OnGetDataFromString(const char * stringOutput)
   {
      char * end;
      if(strchr(stringOutput, '.'))
      {
         float percent = (float)strtod(stringOutput, &end);

         if(end != stringOutput)
         {
            this.percent = percent;
            type = relative;
            return true;
         }
      }
      else if(stringOutput[0])
      {
         int distance = strtol(stringOutput, &end, 0);
         if(end != stringOutput)
         {
            this.distance = distance;
            type = offset;
            return true;
         }
      }
      else
      {
         distance = 0;
         type = 0;
         return true;
      }
      return false;
   }
};

public struct MiddleAnchorValue
{
   AnchorValueType type;

   union
   {
      int distance;
      float percent;
   };
   property MinMaxValue
   {
      set { distance = value; type = none; }
      get { return distance; }
   }
   property int
   {
      set { distance = value; type = none; }
      get { return distance; }
   }
   property double
   {
      set { percent = (float) value; type = middleRelative; }
      get { return (double) percent; }
   }

   const char * OnGetString(char * stringOutput, void * fieldData, ObjectNotationType * onType)
   {
      if(type == middleRelative)
      {
         int c;
         int last = 0;
         sprintf(stringOutput, "%f", percent);
         c = strlen(stringOutput)-1;
         for( ; c >= 0; c--)
         {
            if(stringOutput[c] != '0')
               last = Max(last, c);
            if(stringOutput[c] == '.')
            {
               if(last == c)
               {
                  stringOutput[c+1] = '0';
                  stringOutput[c+2] = 0;
               }
               else
                  stringOutput[last+1] = 0;
               break;
            }
         }
      }
      else if(type == none && distance)
      {
         sprintf(stringOutput, "%d", distance);
      }
      if(onType) *onType = none;
      return stringOutput;
   }

   bool OnGetDataFromString(const char * stringOutput)
   {
      if(strchr(stringOutput, '.'))
      {
         percent = (float)strtod(stringOutput, null);
         type = middleRelative;
      }
      else
      {
         distance = strtol(stringOutput, null, 0);
         type = none;
      }
      return true;
   }
};

public enum AnchorValueType { none, offset, relative, middleRelative, cascade, vTiled, hTiled };

public struct Anchor
{
   union { AnchorValue left; MiddleAnchorValue horz; };
   union { AnchorValue top; MiddleAnchorValue vert; };
   AnchorValue right, bottom;

   const char * OnGetString(char * stringOutput, void * fieldData, ObjectNotationType * onType)
   {
      char tempString[256];
      const char * anchorValue;
      ObjectNotationType subNeedClass = none;

      stringOutput[0] = 0;
      tempString[0] = '\0';
      anchorValue = left.OnGetString(tempString, null, &subNeedClass);
      if(anchorValue[0]) { if(stringOutput[0]) strcat(stringOutput, ", "); strcat(stringOutput, "left = "); strcat(stringOutput, anchorValue); }

      //if(((!left.type && !right.type) && horz.distance) || horz.type == middleRelative)
      if(!right.type && ((!left.type && horz.distance) || horz.type == middleRelative))
      {
         tempString[0] = '\0';
         anchorValue = horz.OnGetString(tempString, null, &subNeedClass);
         if(anchorValue[0]) { if(stringOutput[0]) strcat(stringOutput, ", "); strcat(stringOutput, "horz = "); strcat(stringOutput, anchorValue); }
      }

      tempString[0] = '\0';
      anchorValue = top.OnGetString(tempString, null, &subNeedClass);
      if(anchorValue[0]) { if(stringOutput[0]) strcat(stringOutput, ", "); strcat(stringOutput, "top = "); strcat(stringOutput, anchorValue); }

      tempString[0] = '\0';
      anchorValue = right.OnGetString(tempString, null, &subNeedClass);
      if(anchorValue[0]) { if(stringOutput[0]) strcat(stringOutput, ", "); strcat(stringOutput, "right = "); strcat(stringOutput, anchorValue); }

      // if(((!top.type && !bottom.type) && vert.distance) || vert.type == middleRelative)
      if(!bottom.type && ((!top.type && vert.distance) || vert.type == middleRelative))
      {
         tempString[0] = '\0';
         anchorValue = vert.OnGetString(tempString, null, &subNeedClass);
         if(anchorValue[0]) { if(stringOutput[0]) strcat(stringOutput, ", "); strcat(stringOutput, "vert = "); strcat(stringOutput, anchorValue); }
      }

      tempString[0] = '\0';
      anchorValue = bottom.OnGetString(tempString, null, &subNeedClass);
      if(anchorValue[0]) { if(stringOutput[0]) strcat(stringOutput, ", "); strcat(stringOutput, "bottom = "); strcat(stringOutput, anchorValue); }

      return stringOutput;
   }

   bool OnGetDataFromString(const char * string)
   {
      this = Anchor {};
      return class::OnGetDataFromString(string);
   }
};
