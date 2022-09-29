package renderer

import "core:c"
import "../common"

//---------------------------------------------------------------------------//

MeshDesc :: struct {
	name:   common.Name,
	flags:  MeshFlags,
	thread: u8,
	frame:  u8,
}

//---------------------------------------------------------------------------//

@(private)
MeshFlagBits :: enum u8 {
	Primary,
}

@(private)
MeshFlags :: distinct bit_set[MeshFlagBits;u8]

//---------------------------------------------------------------------------//

MeshResource :: struct {
	desc: MeshDesc,
}

//---------------------------------------------------------------------------//

MeshRef :: Ref(MeshResource)

//---------------------------------------------------------------------------//

InvalidMeshRef := MeshRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_COMMAND_BUFFER_REF_ARRAY: RefArray(MeshResource)

//---------------------------------------------------------------------------//
