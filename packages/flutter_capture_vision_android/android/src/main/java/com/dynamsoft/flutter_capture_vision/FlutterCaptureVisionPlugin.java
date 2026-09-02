package com.dynamsoft.flutter_capture_vision;

import android.content.Context;
import android.graphics.Point;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.dynamsoft.core.basic_structures.ImageData;
import com.dynamsoft.core.basic_structures.Quadrilateral;
import com.dynamsoft.cvr.CaptureVisionRouter;
import com.dynamsoft.cvr.CaptureVisionRouterException;
import com.dynamsoft.cvr.CapturedResult;
import com.dynamsoft.dbr.BarcodeResultItem;
import com.dynamsoft.dbr.DecodedBarcodesResult;
import com.dynamsoft.dcp.ParsedResult;
import com.dynamsoft.dcp.ParsedResultItem;
import com.dynamsoft.ddn.DetectedQuadResultItem;
import com.dynamsoft.ddn.ProcessedDocumentResult;
import com.dynamsoft.dlr.RecognizedTextLinesResult;
import com.dynamsoft.dlr.TextLineResultItem;
import com.dynamsoft.license.LicenseManager;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Android bridge for Capture Vision.
 *
 * <p>All SDK calls, including lifecycle and settings operations, are serialized
 * on {@link #worker}. Capture Vision routers keep mutable template state, and
 * barcode/MRZ/document detection may take tens of milliseconds. Keeping that
 * work off the platform thread prevents camera preview jank and ensures a
 * settings update cannot race an in-flight capture.</p>
 */
public final class FlutterCaptureVisionPlugin implements FlutterPlugin,
        MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "flutter_capture_vision";

    private MethodChannel channel;
    private Context context;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private CaptureVisionRouter router;
    private boolean initialized;
    private boolean mrzSettingsImported;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        context = null;
        worker.shutdownNow();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("initialize".equals(call.method)) {
            final Map<String, Object> arguments = arguments(call);
            final String licenseKey;
            try {
                licenseKey = requiredString(arguments, "licenseKey");
            } catch (VisionException error) {
                postError(result, error);
                return;
            }
            initializeAsync(licenseKey, result);
            return;
        }

        final Map<String, Object> arguments;
        try {
            arguments = arguments(call);
        } catch (VisionException error) {
            postError(result, error);
            return;
        }

        worker.execute(() -> {
            try {
                switch (call.method) {
                    case "initSettings":
                        requireInitialized();
                        requireRouter().initSettings(requiredString(arguments, "settingsJson"));
                        postSuccess(result, null);
                        break;
                    case "resetSettings":
                        requireInitialized();
                        requireRouter().resetSettings();
                        postSuccess(result, null);
                        break;
                    case "captureFile":
                        requireInitialized();
                        postSuccess(result, captureFile(
                                requiredString(arguments, "path"), templatesForRequest(arguments)));
                        break;
                    case "captureBuffer":
                        requireInitialized();
                        postSuccess(result, captureBuffer(arguments));
                        break;
                    case "dispose":
                        // The Java SDK owns the router's native lifetime. Marking this
                        // bridge uninitialized prevents further work after disposal.
                        initialized = false;
                        postSuccess(result, null);
                        break;
                    default:
                        mainHandler.post(result::notImplemented);
                        break;
                }
            } catch (VisionException error) {
                postError(result, error);
            } catch (Exception error) {
                postError(result, new VisionException("native_error", error.getMessage()));
            }
        });
    }

    private void initializeAsync(String licenseKey, MethodChannel.Result result) {
        worker.execute(() -> {
            final Context applicationContext = context;
            if (applicationContext == null) {
                postError(result, new VisionException("detached", "The plugin is detached."));
                return;
            }
            LicenseManager.initLicense(licenseKey, applicationContext, (isSuccess, error) ->
                    worker.execute(() -> {
                        if (isSuccess) {
                            if (router == null) router = new CaptureVisionRouter();
                            initialized = true;
                            postSuccess(result, null);
                        } else {
                            final String message = error == null
                                    ? "Unable to initialize the Dynamsoft license."
                                    : error.getMessage();
                            postError(result, new VisionException("license_error", message));
                        }
                    }));
        });
    }

    private Map<String, Object> captureFile(String path, List<String> templates) {
        Map<String, Object> output = emptyResult();
        for (String template : templates) {
            selectSettings(template);
            appendResult(requireCaptureResult(requireRouter().capture(path, template), template), output);
        }
        return output;
    }

    /// The MRZ Scanner bundle ships `mrzscanner-mobile-templates.json`, whose
    /// MRZ tasks are wired to its bundled models; the factory presets alone
    /// cannot localize MRZ text. The template document replaces the factory
    /// presets, so restore them before any built-in template capture.
    private void selectSettings(String template) {
        try {
            if ("ReadPassportAndId".equals(template)) {
                if (mrzSettingsImported) return;
                requireRouter().initSettingsFromFile(
                        "mrzscanner-mobile-templates.json");
                mrzSettingsImported = true;
            } else if (mrzSettingsImported) {
                requireRouter().resetSettings();
                mrzSettingsImported = false;
            }
        } catch (CaptureVisionRouterException error) {
            throw new VisionException(
                    String.valueOf(error.getErrorCode()),
                    "Unable to switch Capture Vision settings: "
                            + error.getMessage());
        }
    }

    private Map<String, Object> captureBuffer(Map<String, Object> arguments) {
        Map<String, Object> buffer = requiredMap(arguments, "buffer");
        Object rawBytes = buffer.get("bytes");
        if (!(rawBytes instanceof byte[])) {
            throw new VisionException("invalid_argument", "Buffer bytes must be Uint8List.");
        }
        // The MethodChannel payload must not outlive this call's ownership. Make
        // an explicit copy before the worker enters the DCV native layer.
        byte[] bytes = Arrays.copyOf((byte[]) rawBytes, ((byte[]) rawBytes).length);
        ImageData imageData = new ImageData();
        imageData.bytes = bytes;
        imageData.width = requiredInt(buffer, "width");
        imageData.height = requiredInt(buffer, "height");
        imageData.stride = requiredInt(buffer, "stride");
        imageData.format = pixelFormat(requiredString(buffer, "pixelFormat"));
        imageData.orientation = requiredInt(buffer, "rotation");
        if (bytes.length == 0 || imageData.width <= 0 || imageData.height <= 0
                || imageData.stride <= 0) {
            throw new VisionException("invalid_argument", "The image buffer has invalid geometry.");
        }

        Map<String, Object> output = emptyResult();
        for (String template : templatesForRequest(arguments)) {
            selectSettings(template);
            appendResult(requireCaptureResult(requireRouter().capture(imageData, template), template), output);
        }
        return output;
    }

    private CapturedResult requireCaptureResult(CapturedResult captured, String template) {
        if (captured == null) {
            throw new VisionException("capture_failed", "DCV returned no result for template '" + template + "'.");
        }
        if (captured.getErrorCode() != 0) {
            throw new VisionException(String.valueOf(captured.getErrorCode()), captured.getErrorMessage());
        }
        return captured;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> emptyResult() {
        Map<String, Object> output = new HashMap<>();
        output.put("barcodes", new ArrayList<Map<String, Object>>());
        output.put("mrzResults", new ArrayList<Map<String, Object>>());
        output.put("documentDetections", new ArrayList<Map<String, Object>>());
        return output;
    }

    @SuppressWarnings("unchecked")
    private static void appendResult(CapturedResult captured, Map<String, Object> output) {
        List<Map<String, Object>> barcodes = (List<Map<String, Object>>) output.get("barcodes");
        DecodedBarcodesResult barcodeResult = captured.getDecodedBarcodesResult();
        if (barcodeResult != null && barcodeResult.getItems() != null) {
            for (BarcodeResultItem item : barcodeResult.getItems()) {
                if (item == null) continue;
                Map<String, Object> value = new HashMap<>();
                value.put("format", safeString(item.getFormatString()));
                value.put("text", safeString(item.getText()));
                value.put("rawBytes", item.getBytes() == null ? new byte[0] : item.getBytes());
                value.put("confidence", item.getConfidence());
                value.put("location", quadrilateral(item.getLocation()));
                barcodes.add(value);
            }
        }

        List<Map<String, Object>> mrzResults = (List<Map<String, Object>>) output.get("mrzResults");
        ParsedResult parsedResult = captured.getParsedResult();
        if (parsedResult != null && parsedResult.getItems() != null) {
            for (ParsedResultItem item : parsedResult.getItems()) {
                if (item == null) continue;
                Map<String, String> fields = item.getParsedFields() == null
                        ? new HashMap<>() : new HashMap<>(item.getParsedFields());
                List<String> lines = new ArrayList<>();
                for (String fieldName : Arrays.asList("line1", "line2", "line3")) {
                    String line = fields.get(fieldName);
                    if (line != null && !line.isEmpty()) lines.add(line);
                }
                Map<String, Object> value = new HashMap<>();
                value.put("rawText", String.join("\n", lines));
                value.put("documentType", safeString(item.getCodeType()));
                value.put("fields", fields);
                mrzResults.add(value);
            }
        }
        // The parsed item itself carries no geometry. The MRZ zone is the
        // union of the recognized text-line quads, attached here so overlays
        // can highlight the zone; when the parser produced nothing (low
        // resolution or a damaged zone) the raw lines become the result.
        RecognizedTextLinesResult textLines = captured.getRecognizedTextLinesResult();
        Map<String, Object> mrzZone = null;
        int lowestConfidence = Integer.MAX_VALUE;
        List<String> rawLines = new ArrayList<>();
        if (textLines != null && textLines.getItems() != null) {
            List<Point> zonePoints = new ArrayList<>();
            for (TextLineResultItem item : textLines.getItems()) {
                if (item == null) continue;
                String text = safeString(item.getText());
                if (!text.isEmpty()) rawLines.add(text);
                Quadrilateral location = item.getLocation();
                if (location != null && location.points != null) {
                    for (Point point : location.points) {
                        if (point != null) zonePoints.add(point);
                    }
                }
                lowestConfidence = Math.min(lowestConfidence, item.getConfidence());
            }
            if (!zonePoints.isEmpty()) mrzZone = quadrilateralFromPoints(zonePoints);
        }
        if (!mrzResults.isEmpty()) {
            if (mrzZone != null) mrzResults.get(0).put("location", mrzZone);
            if (lowestConfidence != Integer.MAX_VALUE) {
                mrzResults.get(0).put("confidence", lowestConfidence);
            }
        } else if (!rawLines.isEmpty() && mrzZone != null) {
            Map<String, Object> value = new HashMap<>();
            value.put("rawText", String.join("\n", rawLines));
            value.put("documentType", "");
            value.put("fields", new HashMap<String, String>());
            value.put("location", mrzZone);
            value.put("confidence", lowestConfidence == Integer.MAX_VALUE ? 0 : lowestConfidence);
            mrzResults.add(value);
        }

        List<Map<String, Object>> detections =
                (List<Map<String, Object>>) output.get("documentDetections");
        ProcessedDocumentResult documentResult = captured.getProcessedDocumentResult();
        if (documentResult != null && documentResult.getDetectedQuadResultItems() != null) {
            for (DetectedQuadResultItem item : documentResult.getDetectedQuadResultItems()) {
                if (item == null) continue;
                Map<String, Object> value = new HashMap<>();
                value.put("confidence", item.getConfidenceAsDocumentBoundary());
                value.put("location", quadrilateral(item.getLocation()));
                detections.add(value);
            }
        }
    }

    private static Map<String, Object> quadrilateral(Quadrilateral quad) {
        List<Map<String, Object>> points = new ArrayList<>();
        if (quad != null && quad.points != null) {
            for (Point point : quad.points) {
                if (point == null) continue;
                Map<String, Object> value = new HashMap<>();
                value.put("x", point.x);
                value.put("y", point.y);
                points.add(value);
            }
        }
        return Collections.singletonMap("points", points);
    }

    /// The MRZ zone: the union of the recognized text-line quads.
    private static Map<String, Object> quadrilateralFromPoints(List<Point> zonePoints) {
        int minX = Integer.MAX_VALUE, minY = Integer.MAX_VALUE;
        int maxX = Integer.MIN_VALUE, maxY = Integer.MIN_VALUE;
        for (Point point : zonePoints) {
            if (point == null) continue;
            minX = Math.min(minX, point.x);
            minY = Math.min(minY, point.y);
            maxX = Math.max(maxX, point.x);
            maxY = Math.max(maxY, point.y);
        }
        if (minX == Integer.MAX_VALUE) {
            return Collections.singletonMap("points", new ArrayList<>());
        }
        int[][] corners = {{minX, minY}, {maxX, minY}, {maxX, maxY}, {minX, maxY}};
        List<Map<String, Object>> points = new ArrayList<>();
        for (int[] corner : corners) {
            Map<String, Object> value = new HashMap<>();
            value.put("x", corner[0]);
            value.put("y", corner[1]);
            points.add(value);
        }
        return Collections.singletonMap("points", points);
    }

    private static List<String> templatesForRequest(Map<String, Object> arguments) {
        Map<String, Object> request = requiredMap(arguments, "request");
        String type = requiredString(request, "type");
        if ("template".equals(type)) return Collections.singletonList(requiredString(request, "templateName"));
        if (!"tasks".equals(type)) {
            throw new VisionException("invalid_argument", "Request type must be 'tasks' or 'template'.");
        }
        Object rawTasks = request.get("tasks");
        if (!(rawTasks instanceof List) || ((List<?>) rawTasks).isEmpty()) {
            throw new VisionException("invalid_argument", "A task request requires at least one task.");
        }
        List<String> templates = new ArrayList<>();
        for (Object value : (List<?>) rawTasks) {
            if (!(value instanceof String)) {
                throw new VisionException("invalid_argument", "Every task must be a string.");
            }
            switch ((String) value) {
                case "barcode":
                    templates.add("ReadBarcodes_Default");
                    break;
                case "mrz":
                    templates.add("ReadPassportAndId");
                    break;
                case "documentDetection":
                    templates.add("DetectDocumentBoundaries_Default");
                    break;
                default:
                    throw new VisionException("invalid_argument", "Unknown Capture Vision task: " + value);
            }
        }
        return templates;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> arguments(MethodCall call) {
        // dispose() and resetSettings() carry no arguments.
        if (call.arguments == null) return new HashMap<>();
        if (!(call.arguments instanceof Map)) {
            throw new VisionException("invalid_argument", "Method arguments must be a map.");
        }
        return (Map<String, Object>) call.arguments;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> requiredMap(Map<String, Object> values, String key) {
        Object value = values.get(key);
        if (!(value instanceof Map)) {
            throw new VisionException("invalid_argument", "Missing or invalid map argument: " + key);
        }
        return (Map<String, Object>) value;
    }

    private static String requiredString(Map<String, Object> values, String key) {
        Object value = values.get(key);
        if (!(value instanceof String) || ((String) value).isEmpty()) {
            throw new VisionException("invalid_argument", "Missing or invalid string argument: " + key);
        }
        return (String) value;
    }

    private static int requiredInt(Map<String, Object> values, String key) {
        Object value = values.get(key);
        if (!(value instanceof Number)) {
            throw new VisionException("invalid_argument", "Missing or invalid integer argument: " + key);
        }
        return ((Number) value).intValue();
    }

    private static int pixelFormat(String format) {
        switch (format) {
            case "binary": return 0;
            case "grayscale": return 2;
            case "nv21": return 3;
            case "rgb565": return 4;
            case "rgb555": return 5;
            case "rgb888": return 6;
            case "argb8888": return 7;
            case "abgr8888": return 10;
            case "bgr888": return 12;
            case "nv12": return 14;
            default: throw new VisionException("invalid_argument", "Unsupported image pixel format: " + format);
        }
    }

    private void requireInitialized() {
        if (!initialized) {
            throw new VisionException("not_initialized", "Call initialize() before using Capture Vision.");
        }
    }

    private CaptureVisionRouter requireRouter() {
        if (router == null) {
            throw new VisionException("not_initialized", "Call initialize() before using Capture Vision.");
        }
        return router;
    }

    private void postSuccess(MethodChannel.Result result, Object value) {
        mainHandler.post(() -> result.success(value));
    }

    private void postError(MethodChannel.Result result, VisionException error) {
        mainHandler.post(() -> result.error(error.code, error.getMessage(), null));
    }

    private static String safeString(String value) {
        return value == null ? "" : value;
    }

    private static final class VisionException extends RuntimeException {
        final String code;

        VisionException(String code, String message) {
            super(message == null || message.isEmpty() ? "Capture Vision operation failed." : message);
            this.code = code;
        }
    }
}
