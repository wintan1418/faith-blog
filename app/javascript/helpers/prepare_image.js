// Turns a photo the person just picked into a copy held in memory, ready to
// upload. On Android the picker can hand the app a temporary link to a gallery
// photo (Google Photos, cloud or recent shots); if it expires while they write
// a long post, the upload fails on the phone and nothing reaches the server.
// Copying the bytes at pick time avoids that. Big camera photos are also
// scaled down (longest side 2560px, JPEG) so they send quickly on mobile data.
const MAX_SIDE = 2560
const SHRINK_OVER_BYTES = 1.5 * 1024 * 1024
const KEEP_AS_IS = /^image\/(gif|svg\+xml)$/

export async function prepareImage(file) {
  if (!file || !file.type?.startsWith("image/")) return file
  const bytes = await file.arrayBuffer() // throws if the photo can't be read any more
  const copy = new File([ bytes ], file.name || "photo.jpg", { type: file.type, lastModified: file.lastModified || Date.now() })
  if (KEEP_AS_IS.test(file.type)) return copy

  try {
    const bitmap = await createImageBitmap(copy, { imageOrientation: "from-image" })
    const longest = Math.max(bitmap.width, bitmap.height)
    if (longest <= MAX_SIDE && copy.size <= SHRINK_OVER_BYTES) { bitmap.close?.(); return copy }

    const scale = Math.min(1, MAX_SIDE / longest)
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close?.()
    // PNGs stay PNG (they may be see-through); everything else becomes JPEG.
    const type = file.type === "image/png" ? "image/png" : "image/jpeg"
    const blob = await new Promise(resolve => canvas.toBlob(resolve, type, 0.85))
    // Smaller in pixels always wins; same size only if the file got smaller.
    if (!blob || (scale === 1 && blob.size >= copy.size)) return copy
    const name = (file.name || "photo").replace(/\.[^.]+$/, "") + (type === "image/png" ? ".png" : ".jpg")
    return new File([ blob ], name, { type, lastModified: copy.lastModified })
  } catch {
    return copy // a format the web view can't draw (e.g. HEIC): send the original bytes
  }
}
