package renderer

import "core:testing"
import "core:fmt"

@(test)
ast_hover_default_intialized_parameter :: proc(t: ^testing.T) {
	x := 1 + 3

	if x != 4 {
		testing.error(t, "Test tailed")		
	}
}