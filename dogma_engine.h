#ifndef DOGMA_ENGINE_H
#define DOGMA_ENGINE_H

#include <stdint.h>

typedef struct DogmaEngineHandle DogmaEngineHandle;

/// Loads SDE protobuf files from pb_dir (must contain the four .pb2 files).
/// Returns NULL if the directory is invalid or files are missing.
DogmaEngineHandle *dogma_engine_create(const char *pb_dir);

/// Releases all memory held by the engine handle.
void dogma_engine_destroy(DogmaEngineHandle *handle);

/// Calculates ship stats for the given fit and skills (both JSON strings).
/// Returns a JSON string the caller must free with dogma_engine_free_string.
/// Returns NULL on any error.
char *dogma_engine_calculate(const DogmaEngineHandle *handle,
                             const char *fit_json,
                             const char *skills_json);

/// Frees a string returned by dogma_engine_calculate.
void dogma_engine_free_string(char *s);

#endif /* DOGMA_ENGINE_H */
