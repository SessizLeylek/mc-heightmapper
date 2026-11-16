package main

import "core:bytes"
import "core:compress/zlib"
import "core:encoding/endian"
import "core:fmt"
import vmem "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "vendor:stb/image"

import "nbt"

// Structure to hold extracted heightmap data for a single chunk
Chunk_Heightmap :: struct {
	x:       int,
	z:       int,
	heights: [256]u16,
}

generate_png_of_mca :: proc(mca_filepath: string, png_filepath: cstring, height_cutoff: i32 = 0) {
	file_data, err := os.read_entire_file(mca_filepath, context.allocator)
	if err != nil {
		fmt.eprintln("Failed to read MCA file:", mca_filepath)
		return
	}
	defer delete(file_data)

	W :: 512
	H :: 512
	C :: 1
	pixels := make([]u8, W * H * C)
	defer delete(pixels)

	// Iterate through all 32x32 chunks in the region file
	for cx := 0; cx < 32; cx += 1 {
		for cz := 0; cz < 32; cz += 1 {
			header_index := (cx + cz * 32) * 4
			if header_index + 4 > len(file_data) do continue

			// Read 3-byte offset and 1-byte sector count
			offset :=
				u32(file_data[header_index]) << 16 |
				u32(file_data[header_index + 1]) << 8 |
				u32(file_data[header_index + 2])
			sectors := file_data[header_index + 3]

			if offset == 0 || sectors == 0 do continue // Chunk not generated

			chunk_file_offset := int(offset) * 4096
			if chunk_file_offset + 5 > len(file_data) do continue

			// Read chunk length and compression type
			length, ok := endian.get_u32(file_data[chunk_file_offset:], .Big)
			if !ok {
				fmt.eprintln("Chunk length read error")
			}

			compression_type := file_data[chunk_file_offset + 4]

			payload_start := chunk_file_offset + 5
			payload_end := payload_start + int(length) - 1
			if payload_end > len(file_data) do continue

			compressed_payload := file_data[payload_start:payload_end]

			nbt_data: []byte
			decompressed_buf: bytes.Buffer
			defer bytes.buffer_destroy(&decompressed_buf)

			switch compression_type {
			case 2:
				// ZLIB
				err := zlib.inflate_from_byte_array(compressed_payload, &decompressed_buf)
				if err != nil {
					fmt.eprintln("ZLIB decode error", err)
				}
				nbt_data = bytes.buffer_to_bytes(&decompressed_buf)

			case 1:
				// GZIP
				fmt.eprintln("This chunk uses GZIP compression which is not implented yet!")

			case 3:
				// uncompressed
				nbt_data = compressed_payload[:]

			case 4:
				// LZ4
				fmt.eprintln("This chunk uses LZ4 compression which is not implented yet!")

			case:
				fmt.eprintfln(
					"Unexpected compression type %v at chunk [%v, %v]",
					compression_type,
					cx,
					cz,
				)
			}

			{
				// Normally I was thinking of having nbt library to explicitly take the allocator
				// But I didn't have time for that at the time and now I don't want to do an update on it
				// This section should be updated when I do that update to nbt library

				/*pool: mem.Dynamic_Arena
				mem.dynamic_arena_init(&pool)
				arena_alloc := mem.dynamic_arena_allocator(&pool)*/

				arena: vmem.Arena
				assert(vmem.arena_init_growing(&arena) == nil)
				defer vmem.arena_destroy(&arena)

				context.allocator = vmem.arena_allocator(&arena)

				parsed_nbt := nbt.parse_nbt(bytes.buffer_to_bytes(&decompressed_buf))
				heightmaps_compound, ok2 := parsed_nbt.root["Heightmaps"].(nbt.TagCompound)
				if ok2 {
					world_surface, ok3 := heightmaps_compound["MOTION_BLOCKING"].(nbt.TagLongArray)
					if ok3 {
						draw_block_heights_from_nbt_heightmap(world_surface, &pixels, cx, cz, 28)
					}
				}
			}

		}
	}

	// Write out to PNG via stb_image_write
	stride :: W * C
	success := image.write_png(png_filepath, i32(W), i32(H), i32(C), raw_data(pixels), i32(stride))

	if success != 0 {
		fmt.println("Successfully saved image:\e[93m", png_filepath, "\e[0m")
	} else {
		fmt.println("\e[32mFailed to write PNG\e[0m")
		fmt.println(image.failure_reason())
	}
}

// Remember to free!
draw_block_heights_from_nbt_heightmap :: proc(
	nbt_heightmap: []nbt.TagLong,
	pixels: ^[]u8,
	chunk_x: int,
	chunk_z: int,
	height_cutoff: i32 = 0,
) {

	for i in 0 ..< 256 {
		long_index := i / 7
		entry_index := i % 7
		bit_offset := entry_index * 9

		value_unclamped := i32(nbt_heightmap[long_index] >> u16(bit_offset)) & 0x1FF

		value := u8(min(max(value_unclamped - height_cutoff, 0), 255))

		x := (i % 16) + (chunk_x * 16)
		y := (i / 16) + (chunk_z * 16)
		pixels[x + y * 512] = value
	}
}

read_line :: proc(prompt: string, read_buffer: []byte) -> string {
	fmt.print(prompt)
	fmt.print("\e[92m")
	n, err := os.read(os.stdin, read_buffer[:])
	fmt.print("\e[0m")

	if err != os.ERROR_NONE {
		fmt.eprintln("\n\eError reading input: ", err)
		return ""
	}

	return strings.trim(string(read_buffer[:n]), "\r\n ")
}

main :: proc() {

	read_buffer: [256]byte
	read_regions: [dynamic][2]int

	region_folder_path: string

	{
		world_name := strings.clone(read_line("Enter the world folder name: ", read_buffer[:]))
		defer delete(world_name)

		dimension_idx: int
		if result, ok := strconv.parse_int(
			read_line(
				"Which dimension? \e[3m(0: Overworld, 1: Nether, 2: The End)\e[23m: ",
				read_buffer[:],
			),
		); ok && result >= 0 && result <= 2 {
			dimension_idx = result
		} else {
			fmt.printfln("\e[31mThe input (%v) is not valid!\e[0m", result)
			return
		}

		DIMENSION_NAMES := []string{"overworld", "the_nether", "the_end"}
		dimension_name := DIMENSION_NAMES[dimension_idx]

		appdata_path, appdata_err := os.user_data_dir(context.allocator, roaming = true)
		if appdata_err != os.ERROR_NONE {
			fmt.eprintln("User data folder access error!")
			return
		}

		region_folder_path = fmt.aprintf(
			"%v\\.minecraft\\saves\\%v\\dimensions\\minecraft\\%v\\region",
			appdata_path,
			world_name,
			dimension_name,
		)
	}

	defer delete(region_folder_path)
	if !os.exists(region_folder_path) {
		fmt.printfln("\e[31mFolder %v doesn't exist!\e[0m", region_folder_path)
		return
	}

	height_cutoff: i32
	if result, ok := strconv.parse_int(
		read_line(
			"Minimum block height you want \e[3m(That height and the blocks lower will be colored to pitch black)\e[23m: ",
			read_buffer[:],
		),
	); ok {
		height_cutoff = i32(result + 64)
	} else {
		fmt.printfln(
			"\e[31mThe height (%v) is not valid! (It should have been a number between -64 and 319)\e[0m",
			result,
		)
		return
	}

	fmt.println("\n\e[94mSubmit nothing to continue.\e[0m")
	for true {
		line := read_line(
			"Write a region you want the heightmap of \e[3m(i.e. \"-3 -2\")\e[23m: ",
			read_buffer[:],
		)

		if len(line) == 0 {
			break
		}

		region_params := strings.split(line, " ")
		defer delete(region_params)

		if len(region_params) != 2 {
			fmt.printfln(
				"\n\e[31mThe provided input have %v parameters! (Have to be 2)\e[0m",
				len(region_params),
			)
			continue
		}

		region_x, region_y: int

		if x, ok := strconv.parse_int(region_params[0]); !ok {
			fmt.printfln(
				"\n\e[31mFirst provided input %v is not an integer!\e[0m",
				region_params[0],
			)
			continue
		} else do region_x = x

		if y, ok := strconv.parse_int(region_params[1]); !ok {
			fmt.printfln(
				"\n\e[31mSecond provided input %v is not an integer!\e[0m",
				region_params[1],
			)
			continue
		} else do region_y = y

		append(&read_regions, [2]int{region_x, region_y})
	}

	for region in read_regions {
		mca_path := fmt.aprintf("%v\\r.%v.%v.mca", region_folder_path, region[0], region[1])
		png_path := fmt.caprintf(".\\r.%v.%v.png", region[0], region[1])
		defer delete(mca_path)
		defer delete(png_path)

		generate_png_of_mca(mca_path, png_path, height_cutoff)
	}

}
