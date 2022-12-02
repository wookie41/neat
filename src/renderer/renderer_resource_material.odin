
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

MaterialDesc :: struct {
	name:               common.Name,
}

//---------------------------------------------------------------------------//

MaterialResource :: struct {
	desc:                   MaterialDesc,
}

//---------------------------------------------------------------------------//

MaterialRef :: Ref(MaterialResource)

//---------------------------------------------------------------------------//

InvalidMaterialRef := MaterialRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_REF_ARRAY: RefArray(MaterialResource)

//---------------------------------------------------------------------------//

init_materials :: proc() -> bool {
	G_MATERIAL_REF_ARRAY = create_ref_array(MaterialResource, MAX_MATERIALS)
	return true
}

//---------------------------------------------------------------------------//

deinit_materials :: proc() {
}

//---------------------------------------------------------------------------//

create_material :: proc(p_material_ref: MaterialRef) -> bool {
	return true
}

//---------------------------------------------------------------------------//

allocate_material_ref :: proc(p_name: common.Name) -> MaterialRef {
	ref := MaterialRef(create_ref(MaterialResource, &G_MATERIAL_REF_ARRAY, p_name))
	get_material(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material :: proc(p_ref: MaterialRef) -> ^MaterialResource {
	return get_resource(MaterialResource, &G_MATERIAL_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_material :: proc(p_ref: MaterialRef) {
	material := get_material(p_ref)
	free_ref(MaterialResource, &G_MATERIAL_REF_ARRAY, p_ref)
}

