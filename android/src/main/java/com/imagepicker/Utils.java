package com.imagepicker;

import static com.imagepicker.ImagePickerModule.REQUEST_LAUNCH_IMAGE_CAPTURE;
import static com.imagepicker.ImagePickerModule.REQUEST_LAUNCH_LIBRARY;
import static com.imagepicker.ImagePickerModule.REQUEST_LAUNCH_VIDEO_CAPTURE;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.hardware.camera2.CameraCharacteristics;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.text.TextUtils;
import android.util.Base64;
import android.util.Log;
import android.webkit.MimeTypeMap;

import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.FileProvider;
import androidx.exifinterface.media.ExifInterface;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.channels.FileChannel;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import io.microshow.rxffmpeg.RxFFmpegCommandList;
import io.microshow.rxffmpeg.RxFFmpegInvoke;
import io.microshow.rxffmpeg.RxFFmpegSubscriber;

public class Utils {
    public static String fileNamePrefix = "rnImgCache";
    public static String videoFileNamePrefix = "rnVidCache";

    public static String errCameraUnavailable = "camera_unavailable";
    public static String errPermission = "permission";
    public static String errOthers = "others";

    public static String mediaTypePhoto = "photo";
    public static String mediaTypeVideo = "video";

    public static String VIDEO_COMPRESS_EVENT = "VideoCompressEvent";

    public static String cameraPermissionDescription = "This library does not require Manifest.permission.CAMERA, if you add this permission in manifest then you have to obtain the same.";

    public static File createFile(boolean isImage, Context reactContext, String fileType) {
        try {
            String filename = File.separator + (isImage ? fileNamePrefix : videoFileNamePrefix) + File.separator + UUID.randomUUID() + "." + fileType;

            // getCacheDir will auto-clean according to android docs
            File fileDir = reactContext.getCacheDir();

            File file = new File(fileDir, filename);
            File dir = file.getParentFile();
            if (dir != null && !dir.exists()) {
                dir.mkdirs();
            }
            file.createNewFile();
            return file;

        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public static Uri createUri(File file, Context reactContext) {
        String authority = reactContext.getApplicationContext().getPackageName() + ".imagepickerprovider";
        return FileProvider.getUriForFile(reactContext, authority, file);
    }

    public static void saveToPublicDirectory(Uri uri, Context context, String mediaType) {
        ContentResolver resolver = context.getContentResolver();
        Uri mediaStoreUri;
        ContentValues fileDetails = new ContentValues();

        if (mediaType.equals("video")) {
            fileDetails.put(MediaStore.Video.Media.DISPLAY_NAME, UUID.randomUUID().toString());
            fileDetails.put(MediaStore.Video.Media.MIME_TYPE, resolver.getType(uri));
            mediaStoreUri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, fileDetails);
        } else {
            fileDetails.put(MediaStore.Images.Media.DISPLAY_NAME, UUID.randomUUID().toString());
            fileDetails.put(MediaStore.Images.Media.MIME_TYPE, resolver.getType(uri));
            mediaStoreUri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, fileDetails);
        }

        copyUri(uri, mediaStoreUri, resolver);
    }

    public static void copyUri(Uri fromUri, Uri toUri, ContentResolver resolver) {
        try {
            OutputStream os = resolver.openOutputStream(toUri);
            InputStream is = resolver.openInputStream(fromUri);

            byte[] buffer = new byte[8192];
            int bytesRead;

            while ((bytesRead = is.read(buffer)) != -1) {
                os.write(buffer, 0, bytesRead);
            }

        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    // Make a copy of shared storage files inside app specific storage so that users can access it later.
    public static Uri getAppSpecificStorageUri(boolean isImage, Uri sharedStorageUri, Context context) {
        if (sharedStorageUri == null) {
            return null;
        }
        ContentResolver contentResolver = context.getContentResolver();
        String fileType;
        if (isImage) {
            fileType = getFileTypeFromMime(contentResolver.getType(sharedStorageUri));
        } else {
            fileType = getVideoTypeFromMime(contentResolver.getType(sharedStorageUri));
        }
        Uri toUri = Uri.fromFile(createFile(isImage, context, fileType));
        copyUri(sharedStorageUri, toUri, contentResolver);
        return toUri;
    }

    public static boolean isCameraAvailable(Context reactContext) {
        return reactContext.getPackageManager().hasSystemFeature(PackageManager.FEATURE_CAMERA)
                || reactContext.getPackageManager().hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY);
    }

    // Opening front camera is not officially supported in android, the below hack is obtained from various online sources
    public static void setFrontCamera(Intent intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            intent.putExtra("android.intent.extras.CAMERA_FACING", CameraCharacteristics.LENS_FACING_FRONT);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                intent.putExtra("android.intent.extra.USE_FRONT_CAMERA", true);
            }
        } else {
            intent.putExtra("android.intent.extras.CAMERA_FACING", 1);
        }
    }

    public static int[] getImageDimensions(Uri uri, Context reactContext) {
        InputStream inputStream;
        try {
            inputStream = reactContext.getContentResolver().openInputStream(uri);
        } catch (FileNotFoundException e) {
            e.printStackTrace();
            return new int[]{0, 0};
        }

        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeStream(inputStream, null, options);
        return new int[]{options.outWidth, options.outHeight};
    }

    static boolean hasPermission(final Activity activity) {
        final int writePermission = ActivityCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE);
        return writePermission == PackageManager.PERMISSION_GRANTED ? true : false;
    }

    static String getBase64String(Uri uri, Context reactContext) {
        InputStream inputStream;
        try {
            inputStream = reactContext.getContentResolver().openInputStream(uri);
        } catch (FileNotFoundException e) {
            e.printStackTrace();
            return null;
        }

        byte[] bytes;
        byte[] buffer = new byte[8192];
        int bytesRead;
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try {
            while ((bytesRead = inputStream.read(buffer)) != -1) {
                output.write(buffer, 0, bytesRead);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        bytes = output.toByteArray();
        return Base64.encodeToString(bytes, Base64.NO_WRAP);
    }

    // Resize image
    // When decoding a jpg to bitmap all exif meta data will be lost, so make sure to copy orientation exif to new file else image might have wrong orientations
    public static Uri resizeImage(Uri uri, Context context, Options options) {
        try {
            int[] origDimens = getImageDimensions(uri, context);

            if (!shouldResizeImage(origDimens[0], origDimens[1], options)) {
                return uri;
            }

            int width = origDimens[0];
            int height = origDimens[1];

            int inSampleSize;
            if ((width > 1000 && height / width >= 3) || (height > 1000 && width / height >= 3) || width < 1000 || height < 1000) {//max & min
                inSampleSize = 1;
            } else {//center
                inSampleSize = 2;
            }

            BitmapFactory.Options bitmapOptions = new BitmapFactory.Options();
            bitmapOptions.inPreferredConfig = Bitmap.Config.RGB_565;
            bitmapOptions.inSampleSize = inSampleSize;
            Bitmap bitmap = BitmapFactory.decodeFile(uri.getPath(), bitmapOptions);

            String mimeType = getMimeTypeFromFileUri(uri);
            String originalOrientation = getOrientation(uri, context);

            File file = createFile(true, context, getFileTypeFromMime(mimeType));
            OutputStream os = context.getContentResolver().openOutputStream(Uri.fromFile(file));
            bitmap.compress(Bitmap.CompressFormat.WEBP, inSampleSize == 1 ? 75 : 100, os);
            setOrientation(file, originalOrientation, context);
            return Uri.fromFile(file);

        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    static String getOrientation(Uri uri, Context context) throws IOException {
        ExifInterface exifInterface = new ExifInterface(context.getContentResolver().openInputStream(uri));
        return exifInterface.getAttribute(ExifInterface.TAG_ORIENTATION);
    }

    // ExifInterface.saveAttributes is costly operation so don't set exif for unnecessary orientations
    static void setOrientation(File file, String orientation, Context context) throws IOException {
        if (orientation.equals(String.valueOf(ExifInterface.ORIENTATION_NORMAL)) || orientation.equals(String.valueOf(ExifInterface.ORIENTATION_UNDEFINED))) {
            return;
        }
        ExifInterface exifInterface = new ExifInterface(file);
        exifInterface.setAttribute(ExifInterface.TAG_ORIENTATION, orientation);
        exifInterface.saveAttributes();
    }

    static int[] getImageDimensBasedOnConstraints(int origWidth, int origHeight, Options options) {
        int width = origWidth;
        int height = origHeight;

        if (options.maxWidth == 0 || options.maxHeight == 0) {
            return new int[]{width, height};
        }

        if (options.maxWidth < width) {
            height = (int) (((float) options.maxWidth / width) * height);
            width = options.maxWidth;
        }

        if (options.maxHeight < height) {
            width = (int) (((float) options.maxHeight / height) * width);
            height = options.maxHeight;
        }

        return new int[]{width, height};
    }

    static double getFileSize(Uri uri, Context context) {
        try {
            ParcelFileDescriptor f = context.getContentResolver().openFileDescriptor(uri, "r");
            return f.getStatSize();
        } catch (Exception e) {
            e.printStackTrace();
            return 0;
        }
    }

    static int getDuration(Uri uri, Context context) {
        MediaMetadataRetriever m = new MediaMetadataRetriever();
        m.setDataSource(context, uri);
        int duration = Math.round(Float.parseFloat(m.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION))) / 1000;
        m.release();
        return duration;
    }

    static boolean shouldResizeImage(int origWidth, int origHeight, Options options) {
        if ((options.maxWidth == 0 || options.maxHeight == 0) && options.quality == 100) {
            return false;
        }

        if (options.maxWidth >= origWidth && options.maxHeight >= origHeight && options.quality == 100) {
            return false;
        }

        return true;
    }

    static Bitmap.CompressFormat getBitmapCompressFormat(String mimeType) {
        switch (mimeType) {
            case "image/jpeg":
                return Bitmap.CompressFormat.JPEG;
            case "image/png":
                return Bitmap.CompressFormat.PNG;
        }
        return Bitmap.CompressFormat.JPEG;
    }

    static String getFileTypeFromMime(String mimeType) {
        if (mimeType == null) {
            return "jpg";
        }
        switch (mimeType) {
            case "image/jpeg":
                return "jpg";
            case "image/png":
                return "png";
            case "image/gif":
                return "gif";
        }
        return "jpg";
    }

    static String getVideoTypeFromMime(String mimeType) {
        if (mimeType == null) {
            return "mp4";
        }
        if (mimeType.contains("/")) {
            return mimeType.split("/")[1];
        }
        return "mp4";
    }

    static void deleteFile(Uri uri) {
        new File(uri.getPath()).delete();
    }

    static String getMimeTypeFromFileUri(Uri uri) {
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(MimeTypeMap.getFileExtensionFromUrl(uri.toString()));
    }

    // Since library users can have many modules in their project, we should respond to onActivityResult only for our request.
    static boolean isValidRequestCode(int requestCode) {
        switch (requestCode) {
            case REQUEST_LAUNCH_IMAGE_CAPTURE:
            case REQUEST_LAUNCH_VIDEO_CAPTURE:
            case REQUEST_LAUNCH_LIBRARY:
                return true;
            default:
                return false;
        }
    }

    // This library does not require Manifest.permission.CAMERA permission, but if user app declares as using this permission which is not granted, then attempting to use ACTION_IMAGE_CAPTURE|ACTION_VIDEO_CAPTURE will result in a SecurityException.
    // https://issuetracker.google.com/issues/37063818
    public static boolean isCameraPermissionFulfilled(Context context, Activity activity) {
        try {
            String[] declaredPermissions = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), PackageManager.GET_PERMISSIONS)
                    .requestedPermissions;

            if (declaredPermissions == null) {
                return true;
            }

            if (Arrays.asList(declaredPermissions).contains(Manifest.permission.CAMERA)
                    && ActivityCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                return false;
            }

            return true;

        } catch (PackageManager.NameNotFoundException e) {
            e.printStackTrace();
            return true;
        }
    }

    static boolean isImageType(Uri uri, Context context) {
        final String imageMimeType = "image/";

        return getMimeType(uri, context).contains(imageMimeType);
    }

    static boolean isVideoType(Uri uri, Context context) {
        final String videoMimeType = "video/";

        return getMimeType(uri, context).contains(videoMimeType);
    }

    static String getMimeType(Uri uri, Context context) {
        if (uri.getScheme().equals("file")) {
            return getMimeTypeFromFileUri(uri);
        }

        ContentResolver contentResolver = context.getContentResolver();
        return contentResolver.getType(uri);
    }

    static List<Uri> collectUrisFromData(Intent data) {
        // Default Gallery app on older Android versions doesn't support multiple image
        // picking and thus never uses clip data.
        if (data.getClipData() == null) {
            return Collections.singletonList(data.getData());
        }

        ClipData clipData = data.getClipData();
        List<Uri> fileUris = new ArrayList<>(clipData.getItemCount());

        for (int i = 0; i < clipData.getItemCount(); ++i) {
            fileUris.add(clipData.getItemAt(i).getUri());
        }

        return fileUris;
    }

    private static String getFileName(Context context, Uri sourceUri) {
        if (sourceUri == null) return "";
        String fileName = "";
        if (sourceUri.getScheme().contains("content")) {
            try {
                Cursor cursor = context.getContentResolver().query(sourceUri, null, null, null, null);
                if (cursor.moveToFirst()) {
                    fileName = cursor.getString(cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME));
                }
                cursor.close();
            } catch (IllegalArgumentException e) {
                e.printStackTrace();
            }
        } else {
            fileName = sourceUri.getLastPathSegment();
        }
        return fileName;
    }

    static ReadableMap getImageResponseMap(Uri sourceUri, Uri uri, Options options, Context context) {
        String fileName = getFileName(context, sourceUri);
        int[] dimensions = getImageDimensions(uri, context);

        WritableMap map = Arguments.createMap();
        map.putString("sourceURL", sourceUri.toString());
        map.putDouble("sourceFileSize", getFileSize(sourceUri, context));

        map.putDouble("fileSize", getFileSize(uri, context));
        map.putString("fileName", fileName);
        String type = getMimeType(sourceUri, context);
        if (TextUtils.isEmpty(type)) {
            type = getMimeType(uri, context);
        }
        map.putString("type", type);
        if (dimensions[0] == -1) {
            int[] originDimensions = getImageDimensions(sourceUri, context);
            map.putString("uri", sourceUri.toString());
            map.putInt("width", originDimensions[0]);
            map.putInt("height", originDimensions[1]);
        } else {
            map.putString("uri", uri.toString());
            map.putInt("width", dimensions[0]);
            map.putInt("height", dimensions[1]);
        }

        if (options.includeBase64) {
            map.putString("base64", getBase64String(uri, context));
        }
        return map;
    }

    static ReadableMap getVideoResponseMap(Uri sourceUri, Uri uri, Context context, VideoInfo videoInfo) {
        String fileName = getFileName(context, sourceUri);
        WritableMap map = Arguments.createMap();
        map.putString("sourceURL", sourceUri.toString());
        map.putDouble("sourceFileSize", getFileSize(sourceUri, context));
        map.putString("uri", uri.toString());
        map.putDouble("fileSize", getFileSize(uri, context));
        map.putInt("duration", getDuration(uri, context));
        map.putString("fileName", fileName);
        String type = getMimeType(sourceUri, context);
        if (TextUtils.isEmpty(type)) {
            type = getMimeType(uri, context);
        }
        map.putString("type", type);

        //New Add Screenshot & Compress Video
        map.putInt("screenshotWidth", videoInfo.getImgWidth());//截图宽
        map.putInt("screenshotHeight", videoInfo.getImgHeight());//截图高
        map.putString("screenshotPath", videoInfo.getImgPath());//截图地址

        boolean isCompress = videoInfo.isCompress();//是否压缩
        if (isCompress) {
            map.putString("compressVidPath", videoInfo.getCompressVidPath());//压缩视频地址
        }
        map.putBoolean("isCompress", isCompress);//是否压缩视频
        map.putInt("originVidWidth", videoInfo.getVidWidth());//原始视频宽
        map.putInt("originVidHeight", videoInfo.getVidHeight());//原始视频高
        return map;
    }

    /**
     * 获取文件大小
     *
     * @param filePath
     * @return
     */
    public static long getFileSize(String filePath) {
        FileChannel fc = null;
        long fileSize = 0;
        try {
            File f = new File(filePath);
            if (f.exists() && f.isFile()) {
                FileInputStream fis = new FileInputStream(f);
                fc = fis.getChannel();
                fileSize = fc.size();
            } else {
                Log.e("getFileSize", "file doesn't exist or is not a file");
            }
        } catch (FileNotFoundException e) {
            Log.e("getFileSize", e.getMessage());
        } catch (IOException e) {
            Log.e("getFileSize", e.getMessage());
        } finally {
            if (null != fc) {
                try {
                    fc.close();
                } catch (IOException e) {
                    Log.e("getFileSize", e.getMessage());
                }
            }
        }
        return fileSize;
    }

    /**
     * 获取视频缩略图
     *
     * @param uri
     * @param outputPath
     * @return
     */
    public static Screenshot getThumbBoxBlur(Uri uri, int width, int height, int rotate, String outputPath) {
        //关键帧
        //ffmpeg -i video_name_output.mp4 -vf select='eq(pict_type\,I)' -frames:v 1 -vsync vfr -s 750*1334 -f image2 core-%02d.jpeg
        Screenshot screenshot = new Screenshot();
        RxFFmpegCommandList cmdList = new RxFFmpegCommandList();
        cmdList.append("-i");
        cmdList.append(uri.getPath());
        cmdList.append("-vf");
        cmdList.append("select='eq(pict_type\\,I)'");
        cmdList.append("-frames:v");
        cmdList.append("1");
        cmdList.append("-vsync");
        cmdList.append("vfr");
        screenshot.setUri(outputPath);
        if (width >= 1280 || height >= 1280) {
            cmdList.append("-s");
            if (width > height) {
                if (rotate == 0 || rotate == 180) {
                    int w = width * 720 / height;
                    cmdList.append(w + "x720");
                    screenshot.setWidth(w);
                    screenshot.setHeight(720);
                } else {
                    int h = width * 720 / height;
                    cmdList.append("720x" + h);
                    screenshot.setWidth(720);
                    screenshot.setHeight(h);
                }
            } else {
                if (rotate == 0 || rotate == 180) {
                    int h = height * 720 / width;
                    cmdList.append("720x" + h);
                    screenshot.setWidth(720);
                    screenshot.setHeight(h);
                } else {
                    int w = height * 720 / width;
                    cmdList.append(w + "x720");
                    screenshot.setWidth(w);
                    screenshot.setHeight(720);
                }
            }
        } else {
            screenshot.setWidth(width);
            screenshot.setHeight(height);
        }
        cmdList.append("-f");
        cmdList.append("image2");
        cmdList.append("-preset");//转码速度，ultrafast，superfast，veryfast，faster，fast，medium，slow，slower，
        cmdList.append("superfast");
        cmdList.append(outputPath);
        screenshot.setCmdList(cmdList.build());
        return screenshot;
    }

    /**
     * 获取压缩命令
     *
     * @param uri
     * @param width
     * @param height
     * @param rotate
     * @param outputPath
     * @return
     */
    public static String[] getBoxblur(Uri uri, int width, int height, int rotate, String outputPath) {
        RxFFmpegCommandList cmdList = new RxFFmpegCommandList();
        cmdList.append("-i");
        cmdList.append(uri.getPath());
        cmdList.append("-vf");
        if (width > height) {
            if (rotate == 0 || rotate == 180) {
                cmdList.append("scale=-1:720");
            } else {
                cmdList.append("scale=-1:1280");
            }
        } else {
            if (rotate == 0 || rotate == 180) {
                cmdList.append("scale=720:-1");
            } else {
                cmdList.append("scale=1280:-1");
            }
        }
        cmdList.append("-preset");//转码速度，ultrafast，superfast，veryfast，faster，fast，medium，slow，slower，
        cmdList.append("superfast");
        cmdList.append(outputPath);
        return cmdList.build();
    }

    private static int getMetaDataValue(MediaMetadataRetriever retriever, int key) {
        if (retriever == null) return -1;
        return Integer.parseInt(retriever.extractMetadata(key));
    }

    private static void sendEvent(ReactContext reactContext,
                                  String eventName,
                                  @Nullable WritableMap params) {
        reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                .emit(eventName, params);
    }

    private static void compressVideo(final Context context, String[] cmdList,
                                      final String vidPath, final String outputPath,
                                      final long originVideoSize) {
        RxFFmpegInvoke.getInstance()
                .runCommandAsync(cmdList, new RxFFmpegInvoke.IFFmpegListener() {
                    @Override
                    public void onFinish() {
                        WritableMap params = Arguments.createMap();
                        params.putString("mode", "compressVideo");
                        params.putInt("status", 2);
                        long compressVideoSize = getFileSize(outputPath);
                        if (compressVideoSize > originVideoSize) {
                            params.putString("compressVidPath", vidPath);
                        }
                        sendEvent(((ReactContext) context), VIDEO_COMPRESS_EVENT, params);
                    }

                    @Override
                    public void onProgress(int progress, long progressTime) {
                        WritableMap params = Arguments.createMap();
                        params.putString("mode", "compressVideo");
                        params.putInt("status", 1);
                        if (progress < 0) progress = 0;
                        params.putInt("progress", progress);
                        params.putString("progressTime", Long.toString(progressTime / 1000));
                        sendEvent(((ReactContext) context), VIDEO_COMPRESS_EVENT, params);
                    }

                    @Override
                    public void onCancel() {
                        WritableMap params = Arguments.createMap();
                        params.putString("mode", "compressVideo");
                        params.putInt("status", 0);
                        params.putString("msg", "cancel");
                        sendEvent(((ReactContext) context), VIDEO_COMPRESS_EVENT, params);
                    }

                    @Override
                    public void onError(String message) {
                        WritableMap params = Arguments.createMap();
                        params.putString("mode", "compressVideo");
                        params.putInt("status", -1);
                        params.putString("msg", message);
                        sendEvent(((ReactContext) context), VIDEO_COMPRESS_EVENT, params);
                    }
                });
    }

    public static VideoInfo resizeVideo(final Uri uri, final Context context) {
        VideoInfo videoInfo = new VideoInfo();
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        final String vidPath = uri.getPath();
        retriever.setDataSource(vidPath);
        final int width = getMetaDataValue(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH);
        final int height = getMetaDataValue(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT);
        final int rotate = getMetaDataValue(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
        int bitrate = getMetaDataValue(retriever, MediaMetadataRetriever.METADATA_KEY_BITRATE);
        int duration = getMetaDataValue(retriever, MediaMetadataRetriever.METADATA_KEY_DURATION);

        final long originVideoSize = getFileSize(vidPath);
        Log.i("YB", "width: " + width + ",height: " + height + ",rotate: " + rotate + ",duration: " + duration + ",size: " + originVideoSize + ",bitrate: " + bitrate);

        //1.获取缩略图 uri、width、height
        String thumbPath = context.getCacheDir().getPath() + File.separator
                + videoFileNamePrefix + File.separator + UUID.randomUUID() + ".jpg";
        Screenshot screenshot = getThumbBoxBlur(uri, width, height, rotate, thumbPath);
        videoInfo.setImgWidth(screenshot.getWidth());
        videoInfo.setImgHeight(screenshot.getHeight());
        videoInfo.setImgPath(thumbPath);

        videoInfo.setVidWidth(width);
        videoInfo.setVidHeight(height);

        //2.视频压缩路径
        final String compressVidPath = context.getCacheDir().getPath() + File.separator
                + videoFileNamePrefix + File.separator + UUID.randomUUID() + ".mp4";

        final boolean isCompress = (width >= 1280 || height >= 1280) && bitrate / 1024 > 3200;
        if (isCompress) {
            videoInfo.setCompress(true);
            videoInfo.setCompressVidPath(compressVidPath);
        } else {
            videoInfo.setCompress(false);
            videoInfo.setOriginVidPath(vidPath);
        }

        //1.生成视频关键帧截图
        RxFFmpegInvoke.getInstance()
                .runCommandRxJava(screenshot.getCmdList())
                .subscribe(new RxFFmpegSubscriber() {
                    @Override
                    public void onFinish() {
                        if (isCompress) {
                            String[] vidCmdList = getBoxblur(uri, width, height, rotate, compressVidPath);
                            compressVideo(context, vidCmdList, vidPath, compressVidPath, originVideoSize);
                        }
                        WritableMap params = Arguments.createMap();
                        params.putString("mode", "screenshot");
                        params.putInt("status", 2);
                        params.putString("msg", "finish");
                        sendEvent(((ReactContext) context), VIDEO_COMPRESS_EVENT, params);
                    }

                    @Override
                    public void onProgress(int progress, long progressTime) {

                    }

                    @Override
                    public void onCancel() {
                        WritableMap params = Arguments.createMap();
                        params.putString("mode", "screenshot");
                        params.putInt("status", 0);
                        params.putString("msg", "cancel");
                        sendEvent(((ReactContext) context), VIDEO_COMPRESS_EVENT, params);
                    }

                    @Override
                    public void onError(String message) {
                        WritableMap params = Arguments.createMap();
                        params.putString("mode", "screenshot");
                        params.putInt("status", -1);
                        params.putString("msg", message);
                        sendEvent(((ReactContext) context), VIDEO_COMPRESS_EVENT, params);
                    }
                });
        return videoInfo;
    }

    static ReadableMap getResponseMap(List<Uri> fileUris, Options options, final Context context) throws RuntimeException {
        WritableArray assets = Arguments.createArray();
        for (int i = 0; i < fileUris.size(); ++i) {
            Uri uri = fileUris.get(i);
            if (isImageType(uri, context)) {
                if (uri.getScheme().contains("content")) {
                    uri = getAppSpecificStorageUri(true, uri, context);
                }
                uri = resizeImage(uri, context, options);
                assets.pushMap(getImageResponseMap(fileUris.get(i), uri, options, context));
            } else if (isVideoType(uri, context)) {
                if (uri.getScheme().contains("content")) {
                    uri = getAppSpecificStorageUri(false, uri, context);
                }
                VideoInfo videoInfo = resizeVideo(uri, context);
                assets.pushMap(getVideoResponseMap(fileUris.get(i), uri, context, videoInfo));
            } else {
                throw new RuntimeException("Unsupported file type");
            }
        }

        WritableMap response = Arguments.createMap();
        response.putArray("assets", assets);
        return response;
    }

    static ReadableMap getErrorMap(String errCode, String errMsg) {
        WritableMap map = Arguments.createMap();
        map.putString("errorCode", errCode);
        if (errMsg != null) {
            map.putString("errorMessage", errMsg);
        }
        return map;
    }

    static ReadableMap getCancelMap() {
        WritableMap map = Arguments.createMap();
        map.putBoolean("didCancel", true);
        return map;
    }

    /**
     * 删除单个文件
     *
     * @param path 被删除文件的路径名
     * @return 删除成功：true / 删除失败：false
     */
    private static boolean deleteSingleFile(String path) {
        File file = new File(path);
        //如果路径名表示的文件是一个标准文件(非文件夹)且存在，则delete
        if (file.isFile() && file.exists()) {
            return file.delete();
        }
        return false;
    }

    /**
     * 删除文件夹下的所有子目录和子文件
     *
     * @param path 被删除文件加的路径名
     * @return 删除成功：true / 删除失败：false
     */
    private static boolean deleteDirectory(String path) {
        boolean flag = false;
        //如果path不以文件分隔符结尾，则增加分隔符
        if (!path.endsWith(File.separator)) {
            path = path + File.separator;
        }
        File file = new File(path);
        //判断路径名表示的是否是文件夹且是否存在
        if (!file.exists() && !file.isDirectory()) {
            return false;
        }
        File[] files = file.listFiles();
        //遍历删除指定文件夹下的所有文件及目录
        for (File file1 : files) {
            if (file1.isFile()) {
                //删除子文件
                flag = deleteSingleFile(file1.getAbsolutePath());
                if (!flag) {
                    break;
                }
            } else {
                //删除子目录,用到递归
                flag = deleteDirectory(file1.getAbsolutePath());
                if (!flag) {
                    break;
                }
            }
        }
        if (!flag) {
            return false;
        }
        return file.delete();
    }

    /**
     * 删除图片缓存
     *
     * @param context
     */
    public static void clearImgCache(Context context) {
        String imgCachePath = context.getCacheDir() + File.separator + fileNamePrefix;
        deleteDirectory(imgCachePath);
    }

    /**
     * 删除视频缓存
     *
     * @param context
     */
    public static void clearVidCache(Context context) {
        String imgCachePath = context.getCacheDir() + File.separator + videoFileNamePrefix;
        deleteDirectory(imgCachePath);
    }
}
