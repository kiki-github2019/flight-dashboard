function img = asyncDecodeFrame(filePath, frameNo, fps)
    % parfeval worker용 비동기 디코딩 (단발성 VR 생성, persistent 미사용)
    % - 단순 fallback 경로용. 실제 hot path는 asyncDecodeFramePersistent
    img = [];
    try
        vr = VideoReader(filePath);
        try
            img = read(vr, frameNo);
        catch
            relTime = (frameNo - 1) / max(1, fps);
            relTime = max(0, min(relTime, vr.Duration - 0.05));
            vr.CurrentTime = relTime;
            if hasFrame(vr)
                img = readFrame(vr);
            end
        end
    catch
        img = [];
    end
end
