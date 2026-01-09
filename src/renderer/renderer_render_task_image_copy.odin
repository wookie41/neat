package renderer

//---------------------------------------------------------------------------//

// This task is responsible for copying an image

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"

//---------------------------------------------------------------------------//

ImageCopyRenderTaskData :: struct {
	name:          common.Name,
	src_image_ref: ImageRef,
	dst_image_ref: ImageRef,
}

//---------------------------------------------------------------------------//

image_copy_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
	p_render_task_functions.create_instance = create_instance
	p_render_task_functions.destroy_instance = destroy_instance
	p_render_task_functions.begin_frame = begin_frame
	p_render_task_functions.end_frame = end_frame
	p_render_task_functions.render = render
}

//---------------------------------------------------------------------------//

@(private = "file")
create_instance :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> (
	res: bool,
) {
	doc_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"name",
	) or_return

	src_image_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"src",
	) or_return

	dst_image_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"dst",
	) or_return

	src_image_ref := image_find(src_image_name)
	if src_image_ref == InvalidImageRef {
		log.warnf("Failed to setup task %s - src image %s not found\n", doc_name, src_image_name)
	}

	dst_image_ref := image_find(dst_image_name)
	if dst_image_ref == InvalidImageRef {
		log.warnf("Failed to setup task %s - src image %s not found\n", doc_name, dst_image_name)
	}
	image_copy_render_task_data := new(
		ImageCopyRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	image_copy_render_task_data^ = ImageCopyRenderTaskData {
		name          = common.create_name(doc_name),
		src_image_ref = src_image_ref,
		dst_image_ref = dst_image_ref,
	}

	image_copy_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	image_copy_render_task.data_ptr = rawptr(image_copy_render_task_data)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	image_copy_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	free(image_copy_render_task.data_ptr, G_RENDERER_ALLOCATORS.resource_allocator)
}

//---------------------------------------------------------------------------//

@(private = "file")
begin_frame :: proc(p_render_task_ref: RenderTaskRef) {
}

//---------------------------------------------------------------------------//

@(private = "file")
end_frame :: proc(p_render_task_ref: RenderTaskRef) {
}

//---------------------------------------------------------------------------//

@(private = "file")
render :: proc(p_render_task_ref: RenderTaskRef, pdt: f32) {

	image_copy_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	image_copy_render_task_data := (^ImageCopyRenderTaskData)(image_copy_render_task.data_ptr)

	gpu_debug_region_begin(get_frame_cmd_buffer_ref(), common.get_string(image_copy_render_task_data.name))
	defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

	image_copy_content(
		get_frame_cmd_buffer_ref(),
		image_copy_render_task_data.src_image_ref,
		image_copy_render_task_data.dst_image_ref,
	)

}

//---------------------------------------------------------------------------//
