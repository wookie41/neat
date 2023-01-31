import sys
import os
from distutils.util import strtobool


file_template = """
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

@(private="file")
INTERNAL : struct {{
	
}}

//---------------------------------------------------------------------------//

{resource_name_capitalized}Desc :: struct {{
	name:               common.Name,
}}

//---------------------------------------------------------------------------//

{resource_name_capitalized}Resource :: struct {{
	using backend_{resource_name_lowercase}: Backend{resource_name_capitalized}Resource,
	desc:                   {resource_name_capitalized}Desc,
}}

//---------------------------------------------------------------------------//

{resource_name_capitalized}Ref :: Ref({resource_name_capitalized}Resource)

//---------------------------------------------------------------------------//

Invalid{resource_name_capitalized}Ref := {resource_name_capitalized}Ref {{
	ref = c.UINT64_MAX,
}}

//---------------------------------------------------------------------------//

@(private = "file")
G_{resource_name_uppercase}_REF_ARRAY: RefArray({resource_name_capitalized}Resource)

//---------------------------------------------------------------------------//

init_{resource_name_lowercase}s :: proc() -> bool {{
	G_{resource_name_uppercase}_REF_ARRAY = create_ref_array({resource_name_capitalized}Resource, MAX_{resource_name_uppercase}S)
	return backend_init_{resource_name_lowercase}s()
}}

//---------------------------------------------------------------------------//

deinit_{resource_name_lowercase}s :: proc() {{
	backend_deinit_{resource_name_lowercase}s()
}}

//---------------------------------------------------------------------------//

create_{resource_name_lowercase} :: proc(p_{resource_name_lowercase}_ref: {resource_name_capitalized}Ref) -> bool {{
	{resource_name_lowercase} := get_{resource_name_lowercase}(p_{resource_name_lowercase}_ref)
	if backend_create_{resource_name_lowercase}(p_{resource_name_lowercase}_ref, {resource_name_lowercase}) == false {{
		free_ref({resource_name_capitalized}Resource, &G_{resource_name_uppercase}_REF_ARRAY, p_{resource_name_lowercase}_ref)
		return false
	}}
	return true
}}

//---------------------------------------------------------------------------//

allocate_{resource_name_lowercase}_ref :: proc(p_name: common.Name) -> {resource_name_capitalized}Ref {{
	ref := {resource_name_capitalized}Ref(create_ref({resource_name_capitalized}Resource, &G_{resource_name_uppercase}_REF_ARRAY, p_name))
	get_{resource_name_lowercase}(ref).desc.name = p_name
	return ref
}}
//---------------------------------------------------------------------------//

get_{resource_name_lowercase} :: proc(p_ref: {resource_name_capitalized}Ref) -> ^{resource_name_capitalized}Resource {{
	return get_resource({resource_name_capitalized}Resource, &G_{resource_name_uppercase}_REF_ARRAY, p_ref)
}}

//--------------------------------------------------------------------------//

destroy_{resource_name_lowercase} :: proc(p_ref: {resource_name_capitalized}Ref) {{
	{resource_name_lowercase} := get_{resource_name_lowercase}(p_ref)
	backend_destroy_{resource_name_lowercase}({resource_name_lowercase})
	free_ref({resource_name_capitalized}Resource, &G_{resource_name_uppercase}_REF_ARRAY, p_ref)
}}

find_{resource_name_lowercase}_by_name :: proc(p_name: common.Name) -> {resource_name_capitalized}Ref {{
	ref := find_ref_by_name({resource_name_capitalized}Resource, &G_{resource_name_uppercase}}_REF_ARRAY, p_name)
	if ref == Invalid{resource_name_capitalized}Ref {{
		return Invalid{resource_name_capitalized}Ref
	}}
	return {resource_name_capitalized}Ref(ref)
}}


"""


vulkan_backend_template = """
package renderer

when USE_VULKAN_BACKEND {{

	//---------------------------------------------------------------------------//

	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	@(private)
	Backend{resource_name_capitalized}Resource :: struct {{
	}}

	//---------------------------------------------------------------------------//


	@(private="file")
	INTERNAL: struct {{
	}}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_{resource_name_lowercase}s :: proc() -> bool {{
		return true
	}}

	//---------------------------------------------------------------------------//

	@(private)
	backend_deinit_{resource_name_lowercase}s :: proc() {{
	}}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_{resource_name_lowercase} :: proc(
		p_ref: {resource_name_capitalized}Ref,
		p_{resource_name_lowercase}: ^{resource_name_capitalized}Resource,
	) -> bool {{
		return true
	}}
	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_{resource_name_lowercase} :: proc(p_{resource_name_lowercase}: ^{resource_name_capitalized}Resource) {{
	}}

}}
"""

file_template_no_backend = """
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

{resource_name_capitalized}Desc :: struct {{
	name:               common.Name,
}}

//---------------------------------------------------------------------------//

{resource_name_capitalized}Resource :: struct {{
	desc:                   {resource_name_capitalized}Desc,
}}

//---------------------------------------------------------------------------//

{resource_name_capitalized}Ref :: Ref({resource_name_capitalized}Resource)

//---------------------------------------------------------------------------//

Invalid{resource_name_capitalized}Ref := {resource_name_capitalized}Ref {{
	ref = c.UINT64_MAX,
}}

//---------------------------------------------------------------------------//

@(private = "file")
G_{resource_name_uppercase}_REF_ARRAY: RefArray({resource_name_capitalized}Resource)

//---------------------------------------------------------------------------//

init_{resource_name_lowercase}s :: proc() -> bool {{
	G_{resource_name_uppercase}_REF_ARRAY = create_ref_array({resource_name_capitalized}Resource, MAX_{resource_name_uppercase}S)
	return true
}}

//---------------------------------------------------------------------------//

deinit_{resource_name_lowercase}s :: proc() {{
}}

//---------------------------------------------------------------------------//

create_{resource_name_lowercase} :: proc(p_{resource_name_lowercase}_ref: {resource_name_capitalized}Ref) -> bool {{
	return true
}}

//---------------------------------------------------------------------------//

allocate_{resource_name_lowercase}_ref :: proc(p_name: common.Name) -> {resource_name_capitalized}Ref {{
	ref := {resource_name_capitalized}Ref(create_ref({resource_name_capitalized}Resource, &G_{resource_name_uppercase}_REF_ARRAY, p_name))
	get_{resource_name_lowercase}(ref).desc.name = p_name
	return ref
}}
//---------------------------------------------------------------------------//

get_{resource_name_lowercase} :: proc(p_ref: {resource_name_capitalized}Ref) -> ^{resource_name_capitalized}Resource {{
	return get_resource({resource_name_capitalized}Resource, &G_{resource_name_uppercase}_REF_ARRAY, p_ref)
}}

//--------------------------------------------------------------------------//

destroy_{resource_name_lowercase} :: proc(p_ref: {resource_name_capitalized}Ref) {{
	{resource_name_lowercase} := get_{resource_name_lowercase}(p_ref)
	free_ref({resource_name_capitalized}Resource, &G_{resource_name_uppercase}_REF_ARRAY, p_ref)
}}

"""

resource_name = sys.argv[1]
backend_needed = strtobool(sys.argv[2])

resource_name_lowercase = resource_name.lower()
resource_name_uppercase = resource_name.upper()
resource_name_capitalized = resource_name.title().replace("_", "")


values = {
	"resource_name_lowercase": resource_name_lowercase,
	"resource_name_uppercase": resource_name_uppercase,
	"resource_name_capitalized": resource_name_capitalized,
}

if backend_needed:

	file_contents = file_template.format(**values)
	with open("../src/renderer/renderer_resource_%s.odin" % resource_name_lowercase, "w+") as f:
		f.write(file_contents)


	vulkan_backend_file_contents = vulkan_backend_template.format(**values)
	with open("../src/renderer/vulkan renderer_resource_%s.odin" % resource_name_lowercase, "w+") as f:
		f.write(vulkan_backend_file_contents)

else:
	file_contents = file_template_no_backend.format(**values)
	with open("../src/renderer/renderer_resource_%s.odin" % resource_name_lowercase, "w+") as f:
		f.write(file_contents)
