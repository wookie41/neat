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
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
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
        "src/third_party/vma/external/vma.cpp"
    ])

    if res != 0:
        print(" Failed to build VMA")
        exit(-1)

    res = run_command_silent([
        "llvm-ar",
        "rc",
        "src/third_party/vma/external/vma.lib",
        "src/third_party/vma/external/vma.o"
    ])

    if res != 0:
        print(" Failed to build VMA")
        exit(-1)

    os.remove("src/third_party/vma/external/vma.o")

    print ("VMA build successfull")

#-----------------------------------------------------------------------#

def main():
    build_vma()

#-----------------------------------------------------------------------#

if __name__ == '__main__':
    main()

#-----------------------------------------------------------------------#
