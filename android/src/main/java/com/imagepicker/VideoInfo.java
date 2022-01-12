package com.imagepicker;

/**
 * 视频信息
 */
public class VideoInfo {

    //截图宽高、路径
    int imgWidth;
    int imgHeight;
    String imgPath;

    //视频宽高，压缩前路径、压缩后路径，是否压缩
    int vidWidth;
    int vidHeight;
    String originVidPath;
    String compressVidPath;
    boolean isCompress;

    public int getImgWidth() {
        return imgWidth;
    }

    public void setImgWidth(int imgWidth) {
        this.imgWidth = imgWidth;
    }

    public int getImgHeight() {
        return imgHeight;
    }

    public void setImgHeight(int imgHeight) {
        this.imgHeight = imgHeight;
    }

    public String getImgPath() {
        return imgPath;
    }

    public void setImgPath(String imgPath) {
        this.imgPath = imgPath;
    }

    public int getVidWidth() {
        return vidWidth;
    }

    public void setVidWidth(int vidWidth) {
        this.vidWidth = vidWidth;
    }

    public int getVidHeight() {
        return vidHeight;
    }

    public void setVidHeight(int vidHeight) {
        this.vidHeight = vidHeight;
    }

    public String getOriginVidPath() {
        return originVidPath;
    }

    public void setOriginVidPath(String originVidPath) {
        this.originVidPath = originVidPath;
    }

    public String getCompressVidPath() {
        return compressVidPath;
    }

    public void setCompressVidPath(String compressVidPath) {
        this.compressVidPath = compressVidPath;
    }

    public boolean isCompress() {
        return isCompress;
    }

    public void setCompress(boolean compress) {
        isCompress = compress;
    }
}
