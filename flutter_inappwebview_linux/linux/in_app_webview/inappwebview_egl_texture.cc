#include "inappwebview_egl_texture.h"

#include <unistd.h>

#include <epoxy/egl.h>
#include <epoxy/gl.h>

#include "../utils/gl_context.h"
#include "../utils/log.h"
#include "in_app_webview.h"

// EGL_EXT_image_dma_buf_import tokens. epoxy's generated EGL header provides
// these on modern systems; keep numeric fallbacks for older epoxy/Khronos
// headers so this file compiles everywhere.
#ifndef EGL_LINUX_DMA_BUF_EXT
#define EGL_LINUX_DMA_BUF_EXT 0x3270
#endif
#ifndef EGL_LINUX_DRM_FOURCC_EXT
#define EGL_LINUX_DRM_FOURCC_EXT 0x3271
#endif
#ifndef EGL_DMA_BUF_PLANE0_FD_EXT
#define EGL_DMA_BUF_PLANE0_FD_EXT 0x3272
#endif
#ifndef EGL_DMA_BUF_PLANE0_OFFSET_EXT
#define EGL_DMA_BUF_PLANE0_OFFSET_EXT 0x3273
#endif
#ifndef EGL_DMA_BUF_PLANE0_PITCH_EXT
#define EGL_DMA_BUF_PLANE0_PITCH_EXT 0x3274
#endif
#ifndef EGL_DMA_BUF_PLANE1_FD_EXT
#define EGL_DMA_BUF_PLANE1_FD_EXT 0x3275
#endif
#ifndef EGL_DMA_BUF_PLANE1_OFFSET_EXT
#define EGL_DMA_BUF_PLANE1_OFFSET_EXT 0x3276
#endif
#ifndef EGL_DMA_BUF_PLANE1_PITCH_EXT
#define EGL_DMA_BUF_PLANE1_PITCH_EXT 0x3277
#endif
#ifndef EGL_DMA_BUF_PLANE2_FD_EXT
#define EGL_DMA_BUF_PLANE2_FD_EXT 0x3278
#endif
#ifndef EGL_DMA_BUF_PLANE2_OFFSET_EXT
#define EGL_DMA_BUF_PLANE2_OFFSET_EXT 0x3279
#endif
#ifndef EGL_DMA_BUF_PLANE2_PITCH_EXT
#define EGL_DMA_BUF_PLANE2_PITCH_EXT 0x327A
#endif
#ifndef EGL_DMA_BUF_PLANE3_FD_EXT
#define EGL_DMA_BUF_PLANE3_FD_EXT 0x3440
#endif
#ifndef EGL_DMA_BUF_PLANE3_OFFSET_EXT
#define EGL_DMA_BUF_PLANE3_OFFSET_EXT 0x3441
#endif
#ifndef EGL_DMA_BUF_PLANE3_PITCH_EXT
#define EGL_DMA_BUF_PLANE3_PITCH_EXT 0x3442
#endif
#ifndef EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT
#define EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT 0x3443
#endif
#ifndef EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT
#define EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT 0x3444
#endif
#ifndef EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT
#define EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT 0x3445
#endif
#ifndef EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT
#define EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT 0x3446
#endif
#ifndef EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT
#define EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT 0x3447
#endif
#ifndef EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT
#define EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT 0x3448
#endif
#ifndef EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT
#define EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT 0x3449
#endif
#ifndef EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT
#define EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT 0x344A
#endif

// Use the shared HasCurrentGLContext from gl_context.h
static gboolean has_current_gl_context() {
  return flutter_inappwebview_plugin::HasCurrentGLContext() ? TRUE : FALSE;
}

/**
 * Zero-copy EGL Image texture implementation.
 *
 * This is the most performant texture implementation for WPE WebKit because:
 *
 * 1. WPE WebKit exports frames as EGL images (backed by DMA-BUF)
 * 2. We bind the EGL image directly to a GL texture using glEGLImageTargetTexture2DOES
 * 3. Flutter samples this texture directly - NO pixel copy at any point!
 *
 * The previous implementation had this flow:
 *   WPE → EGL Image → glReadPixels (GPU→CPU) → glTexImage2D (CPU→GPU) → Flutter
 *
 * This implementation has:
 *   WPE → EGL Image → GL Texture binding → Flutter
 *
 * This eliminates the glReadPixels bottleneck that was causing lag on large textures.
 */

// Private structure for the EGL texture
struct _InAppWebViewEGLTexture {
  FlTextureGL parent_instance;

  // Reference to the webview (not owned)
  flutter_inappwebview_plugin::WebViewType* webview;

  // The GL texture bound to the current EGL image
  GLuint texture_id;
  gboolean texture_initialized;
  uint32_t texture_width;   // Current texture dimensions
  uint32_t texture_height;

  // Current EGL image (weak reference - owned by WPE)
  void* current_egl_image;  // EGLImageKHR
  uint32_t width;
  uint32_t height;
  gboolean has_new_frame;

  // Fallback: pixel buffer for when EGL is not available (SHM mode)
  uint8_t* fallback_buffer;
  size_t fallback_buffer_size;

  // Default texture for when no content is available
  GLuint default_texture_id;
  gboolean default_texture_initialized;

  // Cached function pointer for EGL image binding
  PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES;
  gboolean extension_checked;
  gboolean extension_available;

  // Consumer-side EGLImage re-imported from the WPE dma_buf frame on FLUTTER's
  // current EGL display (the producer EGLImage cannot be bound cross-display).
  void* flutter_egl_image;        // EGLImageKHR
  EGLDisplay flutter_egl_display; // display the image was created on
  uint64_t imported_serial;       // frame serial the image was made from

  // Mutex to protect frame data access
  GMutex mutex;
};

G_DEFINE_TYPE(InAppWebViewEGLTexture, inappwebview_egl_texture, fl_texture_gl_get_type())

// Check and cache the EGL image extension availability
static gboolean check_egl_image_extension(InAppWebViewEGLTexture* self) {
  if (self->extension_checked) {
    return self->extension_available;
  }

  self->extension_checked = TRUE;

  // Check for the extension
  const char* extensions = (const char*)glGetString(GL_EXTENSIONS);
  
  if (extensions != nullptr &&
      (strstr(extensions, "GL_OES_EGL_image") != nullptr ||
       strstr(extensions, "GL_OES_EGL_image_external") != nullptr)) {
    self->glEGLImageTargetTexture2DOES =
        (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    self->extension_available = (self->glEGLImageTargetTexture2DOES != nullptr);
  } else {
    // Try to get the function pointer anyway - epoxy might handle it
    self->glEGLImageTargetTexture2DOES =
        (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    self->extension_available = (self->glEGLImageTargetTexture2DOES != nullptr);
  }

  if (self->extension_available) {
    flutter_inappwebview_plugin::debugLog(
        "InAppWebViewEGLTexture: GL_OES_EGL_image extension available - zero-copy enabled");
  } else {
    flutter_inappwebview_plugin::debugLog(
        "InAppWebViewEGLTexture: GL_OES_EGL_image extension NOT available - falling back to "
        "pixel buffer");
  }

  return self->extension_available;
}

// DRM_FORMAT_MOD_INVALID - when the modifier equals this, the driver uses the
// buffer's implicit modifier and we must NOT pass modifier attribs. Matches
// libdrm's <drm/drm_fourcc.h> definition (kept local to avoid the dep).
static const uint64_t kDrmFormatModInvalid = (static_cast<uint64_t>(1) << 56) - 1;

// Per-plane EGL dma_buf attrib tokens (plane3 is NOT contiguous with 0..2).
static const EGLint kDmaBufPlaneFdAttrib[4] = {
    EGL_DMA_BUF_PLANE0_FD_EXT, EGL_DMA_BUF_PLANE1_FD_EXT,
    EGL_DMA_BUF_PLANE2_FD_EXT, EGL_DMA_BUF_PLANE3_FD_EXT};
static const EGLint kDmaBufPlaneOffsetAttrib[4] = {
    EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGL_DMA_BUF_PLANE1_OFFSET_EXT,
    EGL_DMA_BUF_PLANE2_OFFSET_EXT, EGL_DMA_BUF_PLANE3_OFFSET_EXT};
static const EGLint kDmaBufPlanePitchAttrib[4] = {
    EGL_DMA_BUF_PLANE0_PITCH_EXT, EGL_DMA_BUF_PLANE1_PITCH_EXT,
    EGL_DMA_BUF_PLANE2_PITCH_EXT, EGL_DMA_BUF_PLANE3_PITCH_EXT};
static const EGLint kDmaBufPlaneModLoAttrib[4] = {
    EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
    EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT};
static const EGLint kDmaBufPlaneModHiAttrib[4] = {
    EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
    EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT};

// Destroy the consumer-side EGLImage (if any). Call with self->mutex held.
// Best effort: the display handle may already be gone during shutdown.
static void inappwebview_egl_texture_release_flutter_image(InAppWebViewEGLTexture* self) {
  if (self->flutter_egl_image != nullptr && self->flutter_egl_display != EGL_NO_DISPLAY) {
    static PFNEGLDESTROYIMAGEKHRPROC destroy_image = nullptr;
    if (destroy_image == nullptr) {
      destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    }
    if (destroy_image != nullptr) {
      destroy_image(self->flutter_egl_display,
                    static_cast<EGLImageKHR>(self->flutter_egl_image));
    }
  }
  self->flutter_egl_image = nullptr;
  self->flutter_egl_display = EGL_NO_DISPLAY;
}

// Populate callback - called by Flutter to get the OpenGL texture
static gboolean inappwebview_egl_texture_populate(FlTextureGL* texture, uint32_t* target,
                                                  uint32_t* name, uint32_t* out_width,
                                                  uint32_t* out_height, GError** error) {
  InAppWebViewEGLTexture* self = INAPPWEBVIEW_EGL_TEXTURE(texture);

  g_mutex_lock(&self->mutex);

  // CRITICAL: Verify we have a current GL context before any GL operations.
  if (!has_current_gl_context()) {
    // Return cached texture if available
    if (self->texture_initialized && self->texture_id != 0) {
      *target = GL_TEXTURE_2D;
      *name = self->texture_id;
      *out_width = self->texture_width > 0 ? self->texture_width : 1;
      *out_height = self->texture_height > 0 ? self->texture_height : 1;
      g_mutex_unlock(&self->mutex);
      return TRUE;
    }

    // Return default texture if available
    if (self->default_texture_initialized && self->default_texture_id != 0) {
      *target = GL_TEXTURE_2D;
      *name = self->default_texture_id;
      *out_width = 1;
      *out_height = 1;
      g_mutex_unlock(&self->mutex);
      return TRUE;
    }

    g_mutex_unlock(&self->mutex);
    g_set_error(error, g_quark_from_static_string("InAppWebViewEGLTexture"), 1,
                "No EGL/GL context current - will retry");
    return FALSE;
  }

  // Determine the consumer display and whether the producer's EGLImage can be
  // bound here directly. EGL images are display-specific: WPE imported the
  // frame on ITS display (egl_display_), so binding that image inside Flutter's
  // context on a DIFFERENT display is undefined and renders black. In that
  // case we re-import the frame's dma_buf planes as a NEW EGLImage on Flutter's
  // current display. When the displays match (or no exported frame exists),
  // fall through to the existing zero-copy / legacy path below.
  EGLDisplay buf_dpy = eglGetCurrentDisplay();
  std::shared_ptr<const flutter_inappwebview_plugin::DmabufFrameExport> frame;
  if (self->webview != nullptr) {
    frame = self->webview->GetDmabufFrame();
  }
  const bool same_display =
      self->webview != nullptr &&
      reinterpret_cast<EGLDisplay>(self->webview->GetEglDisplay()) == buf_dpy;

  if (frame && frame->n_planes > 0 && frame->n_planes <= 4 && frame->width > 0 &&
      frame->height > 0 && !same_display) {
    // === Consumer-side re-import of the WPE dma_buf frame ===
    static bool consumer_import_failed = false;
    const bool reimport =
        self->flutter_egl_image == nullptr || self->imported_serial != frame->serial;
    if (reimport && !consumer_import_failed) {
      inappwebview_egl_texture_release_flutter_image(self);
      static PFNEGLCREATEIMAGEKHRPROC create_image = nullptr;
      if (create_image == nullptr) {
        create_image = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
      }
      if (create_image != nullptr) {
        // Max slots: 3 global key/value pairs (6) + 4 planes x 8 (FD/OFFSET/PITCH/
        // MOD_LO/MOD_HI = 5 pairs = 10... conservatively size 64 and guard).
        EGLint attribs[64];
        int ai = 0;
        int dup_fds[4] = {-1, -1, -1, -1};  // temp copies for the create call
        bool ok = true;
        auto put = [&attribs, &ai, &ok](EGLint key, EGLint value) {
          if (ai + 2 > 64) {  // keep room for EGL_NONE terminator
            ok = false;
            return;
          }
          attribs[ai++] = key;
          attribs[ai++] = value;
        };

        put(EGL_WIDTH, static_cast<EGLint>(frame->width));
        put(EGL_HEIGHT, static_cast<EGLint>(frame->height));
        put(EGL_LINUX_DRM_FOURCC_EXT, static_cast<EGLint>(frame->format));

        // Pass explicit modifiers only when known; with the invalid sentinel the
        // driver must use the buffer's implicit modifier (attribs omitted).
        const bool use_modifier = (frame->modifier != kDrmFormatModInvalid);
        for (uint32_t p = 0; p < frame->n_planes && ok; ++p) {
          if (frame->fds[p] < 0) {
            ok = false;
            break;
          }
          const int dfd = ::dup(frame->fds[p]);
          if (dfd < 0) {
            ok = false;
            break;
          }
          dup_fds[p] = dfd;
          put(kDmaBufPlaneFdAttrib[p], static_cast<EGLint>(dfd));
          put(kDmaBufPlaneOffsetAttrib[p], static_cast<EGLint>(frame->offsets[p]));
          put(kDmaBufPlanePitchAttrib[p], static_cast<EGLint>(frame->strides[p]));
          if (use_modifier) {
            put(kDmaBufPlaneModLoAttrib[p],
                static_cast<EGLint>(frame->modifier & 0xFFFFFFFFull));
            put(kDmaBufPlaneModHiAttrib[p], static_cast<EGLint>(frame->modifier >> 32));
          }
        }

        EGLImageKHR img = EGL_NO_IMAGE_KHR;
        if (ok && ai + 1 <= 64) {
          attribs[ai++] = EGL_NONE;
          img = create_image(buf_dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT,
                             static_cast<EGLClientBuffer>(nullptr), attribs);
        }
        // EGL dups the fds internally during create; close our temp copies.
        for (int p = 0; p < 4; ++p) {
          if (dup_fds[p] >= 0) {
            ::close(dup_fds[p]);
            dup_fds[p] = -1;
          }
        }

        if (img != EGL_NO_IMAGE_KHR) {
          self->flutter_egl_image = static_cast<void*>(img);
          self->flutter_egl_display = buf_dpy;
          self->imported_serial = frame->serial;
          self->width = frame->width;  // dma_buf dims are authoritative here
          self->height = frame->height;
        } else {
          consumer_import_failed = true;
          static bool first_fail = true;
          if (first_fail) {
            g_warning("[flutter_inappwebview] populate: consumer-side EGLImage import FAILED "
                      "(egl=%d, attribs_ok=%d), falling back",
                      static_cast<int>(eglGetError()), ok ? 1 : 0);
            first_fail = false;
          }
        }
      }
    }

    // Bind the consumer-side image when we have one.
    if (self->flutter_egl_image != nullptr && check_egl_image_extension(self)) {
      // Drain stale latched GL errors so the post-bind check is meaningful.
      while (glGetError() != GL_NO_ERROR) {
      }

      if (!self->texture_initialized) {
        glGenTextures(1, &self->texture_id);
        self->texture_initialized = TRUE;
      }

      glBindTexture(GL_TEXTURE_2D, self->texture_id);
      self->glEGLImageTargetTexture2DOES(GL_TEXTURE_2D,
                                         static_cast<GLeglImageOES>(self->flutter_egl_image));
      GLenum gl_err = glGetError();
      if (gl_err == GL_NO_ERROR) {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        glBindTexture(GL_TEXTURE_2D, 0);

        self->texture_width = self->width;
        self->texture_height = self->height;

        *target = GL_TEXTURE_2D;
        *name = self->texture_id;
        *out_width = self->width;
        *out_height = self->height;

        self->has_new_frame = FALSE;

        g_mutex_unlock(&self->mutex);
        return TRUE;
      }

      static bool first_bind_fail = true;
      if (first_bind_fail) {
        g_warning("[flutter_inappwebview] populate: consumer EGLImage bind failed (gl=0x%x), "
                  "falling back",
                  static_cast<unsigned>(gl_err));
        first_bind_fail = false;
      }
      // Bind error: unbind and fall through to the pixel fallback below.
      glBindTexture(GL_TEXTURE_2D, 0);
    }
  } else if (self->current_egl_image != nullptr && self->width > 0 && self->height > 0 &&
             check_egl_image_extension(self)) {
    // EXISTING zero-copy path. Valid only when the producer EGLImage lives on
    // the SAME display as Flutter's context (e.g. legacy WPEBackend-FDO).
    flutter_inappwebview_plugin::debugLog(
        "InAppWebViewEGLTexture: using producer EGLImage directly (same-display path), size=" +
        std::to_string(self->width) + "x" + std::to_string(self->height));
    // Create texture if needed
    if (!self->texture_initialized) {
      glGenTextures(1, &self->texture_id);
      self->texture_initialized = TRUE;
    }

    // Bind the EGL image to our texture - ZERO-COPY!
    glBindTexture(GL_TEXTURE_2D, self->texture_id);
    self->glEGLImageTargetTexture2DOES(GL_TEXTURE_2D,
                                       static_cast<GLeglImageOES>(self->current_egl_image));

    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glBindTexture(GL_TEXTURE_2D, 0);

    // Update tracked dimensions
    self->texture_width = self->width;
    self->texture_height = self->height;

    *target = GL_TEXTURE_2D;
    *name = self->texture_id;
    *out_width = self->width;
    *out_height = self->height;
    
    self->has_new_frame = FALSE;

    g_mutex_unlock(&self->mutex);
    return TRUE;
  }

  // Fallback: Try to get pixel buffer from webview (SHM mode)
  if (self->webview != nullptr) {
    uint32_t buf_width = 0;
    uint32_t buf_height = 0;
    size_t required_size = self->webview->GetPixelBufferSize(&buf_width, &buf_height);

    if (required_size > 0 && buf_width > 0 && buf_height > 0) {
      static bool first_fallback = true;
      if (first_fallback) {
        flutter_inappwebview_plugin::debugLog(
            "InAppWebViewEGLTexture: using pixel buffer fallback (SHM mode), size=" +
            std::to_string(buf_width) + "x" + std::to_string(buf_height));
        first_fallback = false;
      }

      // Reallocate fallback buffer if needed
      if (self->fallback_buffer_size < required_size) {
        self->fallback_buffer = static_cast<uint8_t*>(g_realloc(self->fallback_buffer, required_size));
        self->fallback_buffer_size = required_size;
      }

      if (self->fallback_buffer != nullptr) {
        // Copy pixel data from webview
        if (self->webview->CopyPixelBufferTo(self->fallback_buffer, self->fallback_buffer_size,
                                             &buf_width, &buf_height)) {
          // Create texture if needed
          if (!self->texture_initialized) {
            glGenTextures(1, &self->texture_id);
            self->texture_initialized = TRUE;
          }

          // Upload pixel data to texture
          glBindTexture(GL_TEXTURE_2D, self->texture_id);
          
          // Use glTexSubImage2D if size hasn't changed, otherwise glTexImage2D
          if (self->texture_width == buf_width && self->texture_height == buf_height) {
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, buf_width, buf_height,
                            GL_RGBA, GL_UNSIGNED_BYTE, self->fallback_buffer);
          } else {
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, buf_width, buf_height, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE, self->fallback_buffer);
            self->texture_width = buf_width;
            self->texture_height = buf_height;
          }

          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

          glBindTexture(GL_TEXTURE_2D, 0);

          *target = GL_TEXTURE_2D;
          *name = self->texture_id;
          *out_width = buf_width;
          *out_height = buf_height;

          g_mutex_unlock(&self->mutex);
          return TRUE;
        }
      }
    }
  }

  // No frame available yet, use default 1x1 transparent texture
  if (!self->default_texture_initialized) {
    glGenTextures(1, &self->default_texture_id);
    glBindTexture(GL_TEXTURE_2D, self->default_texture_id);
    uint8_t pixel[4] = {0, 0, 0, 0};  // Transparent
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    self->default_texture_initialized = TRUE;
  }

  *target = GL_TEXTURE_2D;
  *name = self->default_texture_id;
  *out_width = 1;
  *out_height = 1;

  g_mutex_unlock(&self->mutex);
  return TRUE;
}

static void inappwebview_egl_texture_dispose(GObject* object) {
  InAppWebViewEGLTexture* self = INAPPWEBVIEW_EGL_TEXTURE(object);

  g_mutex_lock(&self->mutex);

  // Free fallback buffer
  if (self->fallback_buffer != nullptr) {
    g_free(self->fallback_buffer);
    self->fallback_buffer = nullptr;
    self->fallback_buffer_size = 0;
  }

  // Note: We don't call glDeleteTextures here because:
  // 1. The GL context may not be current
  // 2. Flutter's texture registrar will handle texture cleanup
  self->texture_id = 0;
  self->texture_initialized = FALSE;
  self->texture_width = 0;
  self->texture_height = 0;
  self->default_texture_id = 0;
  self->default_texture_initialized = FALSE;
  self->current_egl_image = nullptr;

  // Destroy our consumer-side EGLImage (best effort: the EGL display may
  // already be gone during shutdown; the release helper is null-safe).
  inappwebview_egl_texture_release_flutter_image(self);
  self->imported_serial = 0;

  g_mutex_unlock(&self->mutex);
  g_mutex_clear(&self->mutex);

  G_OBJECT_CLASS(inappwebview_egl_texture_parent_class)->dispose(object);
}

static void inappwebview_egl_texture_class_init(InAppWebViewEGLTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = inappwebview_egl_texture_populate;
  G_OBJECT_CLASS(klass)->dispose = inappwebview_egl_texture_dispose;
}

static void inappwebview_egl_texture_init(InAppWebViewEGLTexture* self) {
  self->webview = nullptr;
  self->texture_id = 0;
  self->texture_initialized = FALSE;
  self->texture_width = 0;
  self->texture_height = 0;
  self->current_egl_image = nullptr;
  self->width = 0;
  self->height = 0;
  self->has_new_frame = FALSE;
  self->fallback_buffer = nullptr;
  self->fallback_buffer_size = 0;
  self->default_texture_id = 0;
  self->default_texture_initialized = FALSE;
  self->glEGLImageTargetTexture2DOES = nullptr;
  self->extension_checked = FALSE;
  self->extension_available = FALSE;
  self->flutter_egl_image = nullptr;
  self->flutter_egl_display = EGL_NO_DISPLAY;
  self->imported_serial = 0;
  g_mutex_init(&self->mutex);
}

InAppWebViewEGLTexture* inappwebview_egl_texture_new(
    flutter_inappwebview_plugin::WebViewType* webview) {
  InAppWebViewEGLTexture* self =
      INAPPWEBVIEW_EGL_TEXTURE(g_object_new(INAPPWEBVIEW_TYPE_EGL_TEXTURE, nullptr));
  self->webview = webview;
  flutter_inappwebview_plugin::debugLog("InAppWebViewEGLTexture: created (zero-copy mode)");
  return self;
}

void inappwebview_egl_texture_set_egl_image(InAppWebViewEGLTexture* self, void* egl_image,
                                            uint32_t width, uint32_t height) {
  if (self == nullptr) {
    return;
  }

  g_mutex_lock(&self->mutex);

  self->current_egl_image = egl_image;
  self->width = width;
  self->height = height;
  self->has_new_frame = TRUE;

  g_mutex_unlock(&self->mutex);
}
