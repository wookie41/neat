/*
---------------------------------------------------------------------------
Open Asset Import Library (assimp)
---------------------------------------------------------------------------

Copyright (c) 2006-2022, assimp team

All rights reserved.

Redistribution and use of this software in source and binary forms,
with or without modification, are permitted provided that the following
conditions are met:

* Redistributions of source code must retain the above
  copyright notice, this list of conditions and the
  following disclaimer.

* Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the
  following disclaimer in the documentation and/or other
  materials provided with the distribution.

* Neither the name of the assimp team, nor the names of its
  contributors may be used to endorse or promote products
  derived from this software without specific prior
  written permission of the assimp team.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
---------------------------------------------------------------------------
*/

/** @file types.h
 *  Basic data types and primitives, such as vectors or colors.
 */
#pragma once
#ifndef AI_TYPES_H_INC
#define AI_TYPES_H_INC

#ifdef __GNUC__
#pragma GCC system_header
#endif

// Some runtime headers
#include <limits.h"
#include <stddef.h"
#include <stdint.h"
#include <string.h"
#include <sys/types.h"

// Our compile configuration
#include "defs.h"

// Some types moved to separate header due to size of operators
#include "vector2.h"
#include "vector3.h"
#include "color4.h"
#include "matrix3x3.h"
#include "matrix4x4.h"
#include "quaternion.h"

typedef int32_t ai_int32;
typedef uint32_t ai_uint32;



/** Maximum dimension for strings, ASSIMP strings are zero terminated. */
#define MAXLEN 1024

// ----------------------------------------------------------------------------------
/** Represents a plane in a three-dimensional, euclidean space
*/
struct aiPlane {


    //! Plane equation
    float a, b, c, d;
}; // !struct aiPlane

// ----------------------------------------------------------------------------------
/** Represents a ray
*/
struct aiRay {
    //! Position and direction of the ray
     aiVector3D pos, dir;
}; // !struct aiRay

// ----------------------------------------------------------------------------------
/** Represents a color in Red-Green-Blue space.
*/
struct aiColor3D {
    //! Red, green and blue color values
    float r, g, b;
}; // !struct aiColor3D

// ----------------------------------------------------------------------------------
/** Represents an UTF-8 string, zero byte terminated.
 *
 *  The character set of an aiString is explicitly defined to be UTF-8. This Unicode
 *  transformation was chosen in the belief that most strings in 3d files are limited
 *  to ASCII, thus the character set needed to be strictly ASCII compatible.
 *
 *  Most text file loaders provide proper Unicode input file handling, special unicode
 *  characters are correctly transcoded to UTF8 and are kept throughout the libraries'
 *  import pipeline.
 *
 *  For most applications, it will be absolutely sufficient to interpret the
 *  aiString as ASCII data and work with it as one would work with a plain char*.
 *  Windows users in need of proper support for i.e asian characters can use the
 *  MultiByteToWideChar(), WideCharToMultiByte() WinAPI functionality to convert the
 *  UTF-8 strings to their working character set (i.e. MBCS, WideChar).
 *
 *  We use this representation instead of std::string to be C-compatible. The
 *  (binary) length of such a string is limited to MAXLEN characters (including the
 *  the terminating zero).
*/
struct aiString {
    /** Binary length of the string excluding the terminal 0. This is NOT the
     *  logical length of strings containing UTF-8 multi-byte sequences! It's
     *  the number of bytes from the beginning of the string to its end.*/
    ai_uint32 length;

    /** String buffer. Size limit is MAXLEN */
    char data[MAXLEN];
}; // !struct aiString

// ----------------------------------------------------------------------------------
/** Standard return type for some library functions.
 * Rarely used, and if, mostly in the C API.
 */
typedef enum aiReturn {
    /** Indicates that a function was successful */
    aiReturn_SUCCESS = 0x0,

    /** Indicates that a function failed */
    aiReturn_FAILURE = -0x1,

    /** Indicates that not enough memory was available
     * to perform the requested operation
     */
    aiReturn_OUTOFMEMORY = -0x3,

    /** @cond never
     *  Force 32-bit size enum
     */
    _AI_ENFORCE_ENUM_SIZE = 0x7fffffff

    /// @endcond
} aiReturn; // !enum aiReturn

// just for backwards compatibility, don't use these constants anymore
#define AI_SUCCESS aiReturn_SUCCESS
#define AI_FAILURE aiReturn_FAILURE
#define AI_OUTOFMEMORY aiReturn_OUTOFMEMORY

// ----------------------------------------------------------------------------------
/** Seek origins (for the virtual file system API).
 *  Much cooler than using SEEK_SET, SEEK_CUR or SEEK_END.
 */
enum aiOrigin {
    /** Beginning of the file */
    aiOrigin_SET = 0x0,

    /** Current position of the file pointer */
    aiOrigin_CUR = 0x1,

    /** End of the file, offsets must be negative */
    aiOrigin_END = 0x2,

    /**  @cond never
     *   Force 32-bit size enum
     */
    _AI_ORIGIN_ENFORCE_ENUM_SIZE = 0x7fffffff

    /// @endcond
}; // !enum aiOrigin

// ----------------------------------------------------------------------------------
/** @brief Enumerates predefined log streaming destinations.
 *  Logging to these streams can be enabled with a single call to
 *   #LogStream::createDefaultStream.
 */
enum aiDefaultLogStream {
    /** Stream the log to a file */
    aiDefaultLogStream_FILE = 0x1,

    /** Stream the log to std::cout */
    aiDefaultLogStream_STDOUT = 0x2,

    /** Stream the log to std::cerr */
    aiDefaultLogStream_STDERR = 0x4,

    /** MSVC only: Stream the log the the debugger
     * (this relies on OutputDebugString from the Win32 SDK)
     */
    aiDefaultLogStream_DEBUGGER = 0x8,

    /** @cond never
     *  Force 32-bit size enum
     */
    _AI_DLS_ENFORCE_ENUM_SIZE = 0x7fffffff
    /// @endcond
}; // !enum aiDefaultLogStream

// just for backwards compatibility, don't use these constants anymore
#define DLS_FILE aiDefaultLogStream_FILE
#define DLS_STDOUT aiDefaultLogStream_STDOUT
#define DLS_STDERR aiDefaultLogStream_STDERR
#define DLS_DEBUGGER aiDefaultLogStream_DEBUGGER

// ----------------------------------------------------------------------------------
/** Stores the memory requirements for different components (e.g. meshes, materials,
 *  animations) of an import. All sizes are in bytes.
 *  @see Importer::GetMemoryRequirements()
*/
struct aiMemoryInfo {

    /** Storage allocated for texture data */
    unsigned int textures;

    /** Storage allocated for material data  */
    unsigned int materials;

    /** Storage allocated for mesh data */
    unsigned int meshes;

    /** Storage allocated for node data */
    unsigned int nodes;

    /** Storage allocated for animation data */
    unsigned int animations;

    /** Storage allocated for camera data */
    unsigned int cameras;

    /** Storage allocated for light data */
    unsigned int lights;

    /** Total storage allocated for the full import. */
    unsigned int total;
}; // !struct aiMemoryInfo

// Include implementation files
#include "vector2.inl"
#include "vector3.inl"
#include "color4.inl"
#include "matrix3x3.inl"
#include "matrix4x4.inl"
#include "quaternion.inl"

#endif // AI_TYPES_H_INC
