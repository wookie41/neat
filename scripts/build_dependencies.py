import os
from re import sub
import subprocess

#-----------------------------------------------------------------------#

VULKAN_SDK_ENV_VAR_NAMES = [
    "VK_SDK_PATH",
    "VULKAN_SDK"
]

#-----------------------------------------------------------------------#

def run_command_silent(args):
    return subprocess.run(
        " ".join(args),
        #stdout=subprocess.DEVNULL,
        #stderr=subprocess.DEVNULL
    ).returncode

#-----------------------------------------------------------------------#

def build_vma():

    print("Building VMA...")

    vulkan_sdk_path = None
    for name in VULKAN_SDK_ENV_VAR_NAMES:
        if name in os.environ:
            vulkan_sdk_path = os.environ[name]
            break

    if vulkan_sdk_path is None:
        print("Failed to find Vulkan SDK")
        exit(-1)

    print(" Using Vulkan SDK %s" % vulkan_sdk_path)

    res = run_command_silent([
        "clang++",
        "-I %s/Include" % vulkan_sdk_path,
        "-c", 
        "-o src/third_party/vma/external/vma.o", 
        "../src/third_party/vma/external/vma.cpp"
    ])

    if res != 0:
        print(" Failed to build VMA")
        exit(-1)

    res = run_command_silent([
        "llvm-ar",
        "rc",
        "../src/third_party/vma/external/vma.lib",
        "../src/third_party/vma/external/vma.o"
    ])

    if res != 0:
        print(" Failed to build VMA")
        exit(-1)

    os.remove("../src/third_party/vma/external/vma.o")

    print("VMA build successfull")

#-----------------------------------------------------------------------#
def build_tinyobj():

    print("Building tiny_obj_loader...")

    res = run_command_silent([
        "clang++",
        "-c", 
        "-o src/third_party/tiny_obj_loader/external/tiny_obj_loader.o", 
        "../src/third_party/tiny_obj_loader/external/tiny_obj_loader.cc"
    ])

    if res != 0:
        print("Failed to build tiny_obj_loader")
        exit(-1)

    res = run_command_silent([
        "llvm-ar",
        "rc",
        "../src/third_party/tiny_obj_loader/external/tiny_obj_loader.lib",
        "../src/third_party/tiny_obj_loader/external/tiny_obj_loader.o"
    ])

    if res != 0:
        print("Failed to build tiny_obj_loader")
        exit(-1)

    os.remove("../src/third_party/tiny_obj_loader/external/tiny_obj_loader.o")

    print("tiny_obj_loader build successfull")


#-----------------------------------------------------------------------#

def build_spirv_reflect():

    print("Building SPRIV-Reflect...")

    res = run_command_silent([
        "clang++",
        "-c", 
        "-o src/third_party/spirv_reflect/external/spirv_reflect.o", 
        "../src/third_party/spirv_reflect/external/spirv_reflect.cpp"
    ])

    if res != 0:
        print("Failed to build SPIRV-Reflect")
        exit(-1)

    res = run_command_silent([
        "llvm-ar",
        "rc",
        "../src/third_party/spirv_reflect/external/spirv_reflect.lib",
        "../src/third_party/spirv_reflect/external/spirv_reflect.o"
    ])

    if res != 0:
        print("Failed to build SPIRV-REFLECT")
        exit(-1)

    os.remove("../src/third_party/spirv_reflect/external/spirv_reflect.o")

    print("SPRIV-Reflect build successfull")

#-----------------------------------------------------------------------#

def build_tinyobjloader():

    print("Building tinydds...")

    res = run_command_silent([
        "clang++",
        "-c", 
        "-o ../src/third_party/tinydds/external/tinydds.o", 
        "../src/third_party/tinydds/external/tinydds.cc"
    ])

    if res != 0:
        print("Failed to build tinydds")
        exit(-1)

    res = run_command_silent([
        "llvm-ar",
        "rc",
        "../src/third_party/tinydds/external/tinydds.lib",
        "../src/third_party/tinydds/external/tinydds.o"
    ])

    if res != 0:
        print("Failed to build tinydds")
        exit(-1)

    os.remove("../src/third_party/tinydds/external/tinydds.o")

    print("tinydds build successfull")

#-----------------------------------------------------------------------#

def main():
    # build_vma()
    # build_tinyobj()
    #build_spirv_reflect()
    build_tinyobjloader()
#-----------------------------------------------------------------------#

if __name__ == '__main__':
    main()

#-----------------------------------------------------------------------#
