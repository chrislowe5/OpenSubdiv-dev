#
#     Copyright 2013 Pixar
#
#     Licensed under the Apache License, Version 2.0 (the "License");
#     you may not use this file except in compliance with the License
#     and the following modification to it: Section 6 Trademarks.
#     deleted and replaced with:
#
#     6. Trademarks. This License does not grant permission to use the
#     trade names, trademarks, service marks, or product names of the
#     Licensor and its affiliates, except as required for reproducing
#     the content of the NOTICE file.
#
#     You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing,
#     software distributed under the License is distributed on an
#     "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
#     either express or implied.  See the License for the specific
#     language governing permissions and limitations under the
#     License.
#

# This file is used by the Android NDK to allow OpenSubdiv libraries
# to be imported by client modules.

LOCAL_PATH:= $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE = OpenSubdivOsdCPU
LOCAL_SRC_FILES = libs/armeabi-v7a/libosdCPU.so
LOCAL_EXPORT_C_INCLUDES = $(LOCAL_PATH)/include

include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)

LOCAL_MODULE = OpenSubdivOsdGPU
LOCAL_SRC_FILES = libs/armeabi-v7a/libosdGPU.so
LOCAL_EXPORT_C_INCLUDES = $(LOCAL_PATH)/include

include $(PREBUILT_SHARED_LIBRARY)

