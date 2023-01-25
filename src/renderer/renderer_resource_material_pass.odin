
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

MaterialPassDesc :: struct {
	name:               common.Name,
}

//---------------------------------------------------------------------------//

MaterialPassResource :: struct {
	desc:                   MaterialPassDesc,
}

//---------------------------------------------------------------------------//

MaterialPassRef :: Ref(MaterialPassResource)

//---------------------------------------------------------------------------//

InvalidMaterialPassRef := MaterialPassRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_PASS_REF_ARRAY: RefArray(MaterialPassResource)

//---------------------------------------------------------------------------//

init_material_passs :: proc() -> bool {
	G_MATERIAL_PASS_REF_ARRAY = create_ref_array(MaterialPassResource, MAX_MATERIAL_PASSES)
	return true
}

//---------------------------------------------------------------------------//

deinit_material_passs :: proc() {
}

//---------------------------------------------------------------------------//

create_material_pass :: proc(p_material_pass_ref: MaterialPassRef) -> bool {
	return true
}

//---------------------------------------------------------------------------//

allocate_material_pass_ref :: proc(p_name: common.Name) -> MaterialPassRef {
	ref := MaterialPassRef(create_ref(MaterialPassResource, &G_MATERIAL_PASS_REF_ARRAY, p_name))
	get_material_pass(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material_pass :: proc(p_ref: MaterialPassRef) -> ^MaterialPassResource {
	return get_resource(MaterialPassResource, &G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_material_pass :: proc(p_ref: MaterialPassRef) {
	// material_pass := get_material_pass(p_ref)
	free_ref(MaterialPassResource, &G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

