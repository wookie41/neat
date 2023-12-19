This readme is so that I don't forget how to set this up when I format my PC or something similar.


### Building

In .vscode/tasks.json, there are the following tasks:
- MakeBinDir - this creates the output directory for the exe
- CopyDlls - copies the necessary DLLs (SDL, assimp etc.) so that the program starts
- Build - build the exe

In case this file gets losed or something, the contents are

```
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "MakeBinDir",
            "type": "shell",
            "windows": {
                "command": "cmd",
                "args": ["/C", "if not exist .\\bin mkdir .\\bin"]
            }
        },
        {
            "label": "CopyDlls",
            "type": "shell",
            "command": "cp src/third_party/assimp/external/assimp-vc143-mt.dll bin/; cp src/third_party/dlls/SDL2.dll bin/",
            "dependsOn": "MakeBinDir",
        },
        {
            "label": "(Debug) Build",
            "type": "shell",
            "command": "odin build src/runner/neat.odin -file --debug -o:minimal --vet-shadowing --vet-unused --vet-style  -out:bin/neat.exe",
            "problemMatcher": [],
            "dependsOn": "CopyDlls",
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
```

### Generating bindings

To generate bindings, simply run `scripts/generate_bindings.exe` **!!! THIS HAS TO BE DONE FROM THE  `src` directory!!!**.

Sadly, the binding generator doesn't recognize `#ifdef`s, so when generating a binding for a stb-like directory, one has to temporary delete all the implementation after the if-guard so the generator doesn't complain.

### Building dependencies

To build dependencies, run `python build_dependencies.py` (again, mind the directory). There's are clang++.exe and llvm-ar.exe bundled, they can be extracted from `scripts/llvm.zip`.
