package com.imagepicker;

import android.text.TextUtils;

import com.facebook.react.bridge.ReadableMap;

public class Options {
    int selectionLimit;
    Boolean includeBase64;
    int videoQuality = 1;
    int quality;
    int maxWidth;
    int maxHeight;
    int screenshotWidth;//压缩图片，且设置压缩图片最大宽度
    Boolean saveToPhotos;
    int durationLimit;
    Boolean useFrontCamera = false;
    String mediaType;
    Boolean isCompressVideo;//是否压缩视频，默认不压缩

    Options(ReadableMap options) {
        mediaType = options.getString("mediaType");
        selectionLimit = options.getInt("selectionLimit");
        includeBase64 = options.getBoolean("includeBase64");

        String videoQualityString = options.getString("videoQuality");
        if (!TextUtils.isEmpty(videoQualityString) && !videoQualityString.toLowerCase().equals("high")) {
            videoQuality = 0;
        }

        if (options.getString("cameraType").equals("front")) {
            useFrontCamera = true;
        }

        quality = (int) (options.getDouble("quality") * 100);
        maxHeight = options.getInt("maxHeight");
        if (options.hasKey("screenshotWidth")) {
            screenshotWidth = options.getInt("screenshotWidth");
        } else {
            screenshotWidth = 0;
        }
        maxWidth = options.getInt("maxWidth");
        saveToPhotos = options.getBoolean("saveToPhotos");
        durationLimit = options.getInt("durationLimit");
        if (options.hasKey("isCompressVideo")) {
            isCompressVideo = options.getBoolean("isCompressVideo");
        } else {
            isCompressVideo = false;
        }
    }
}
