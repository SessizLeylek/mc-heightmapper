package main

import "core:bytes"
import "core:compress/gzip"
import "core:compress/zlib"
import "core:encoding/endian"
import "core:fmt"
import "core:os"
import "vendor:compress/lz4"

import "nbt"

// Structure to hold extracted heightmap data for a single chunk
Chunk_Heightmap :: struct {
	x:       int,
	z:       int,
	heights: [256]u16,
}

parse_mca_file :: proc(filepath: string) {
	file_data, err := os.read_entire_file(filepath, context.allocator)
	if err != nil {
		fmt.eprintln("Failed to read MCA file:", filepath)
		return
	}
	defer delete(file_data)

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


		}
	}
}

main :: proc() {
	/*parse_mca_file(
		"C:\\Users\\kursa\\AppData\\Roaming\\.minecraft\\saves\\balkent\\dimensions\\minecraft\\overworld\\region\\r.0.0.mca",
		)*/

	filepath := "C:\\Users\\kursa\\AppData\\Roaming\\.minecraft\\saves\\balkent\\level.dat"
	file_data, err := os.read_entire_file(filepath, context.allocator)
	if err != nil {
		fmt.eprintln("Failed to read MCA file:", filepath)
		return
	}
	defer delete(file_data)

	buff : bytes.Buffer
	gzip.load_from_bytes(file_data, &buff)
	uncompressed_data := bytes.buffer_to_bytes(&buff)

	read_nbt := nbt.parse_nbt(uncompressed_data)
	fmt.println(read_nbt)
}
