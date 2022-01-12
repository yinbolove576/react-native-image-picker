package com.imagepicker;

/**
 * 视频截图信息
 */
public class Screenshot {

    int width;
    int height;
    String uri;
    String[] cmdList;

    public int getWidth() {
        return width;
    }

    public void setWidth(int width) {
        this.width = width;
    }

    public int getHeight() {
        return height;
    }

    public void setHeight(int height) {
        this.height = height;
    }

    public String getUri() {
        return uri;
    }

    public void setUri(String uri) {
        this.uri = uri;
    }

    public String[] getCmdList() {
        return cmdList;
    }

    public void setCmdList(String[] cmdList) {
        this.cmdList = cmdList;
    }
}
