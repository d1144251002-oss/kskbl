<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <title>斑馬線 AI 離線辨識系統 (ONNX Runtime)</title>
    <!-- 引入 ONNX Runtime Web 官方套件 (CDN) -->
    <script src="https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; background: #f4f4f9; padding: 20px; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        #status { font-weight: bold; color: #2e7d32; margin: 10px 0; }
        canvas { max-width: 100%; height: auto; margin-top: 15px; border: 2px solid #ddd; border-radius: 8px; }
        input[type="file"] { margin: 15px 0; }
    </style>
</head>
<body>

<div class="container">
    <h2>🚦 斑馬線（Crosswalk）離線 AI 辨識系統</h2>
    <div id="status">⏳ 正在載入 ONNX 模型中，請稍候...</div>
    <input type="file" id="imageInput" accept="image/*" disabled>
    <br>
    <canvas id="outputCanvas"></canvas>
</div>

<script>
    let session = null;
    const statusDiv = document.getElementById('status');
    const imageInput = document.getElementById('imageInput');
    const canvas = document.getElementById('outputCanvas');
    const ctx = canvas.getContext('2d');

    // 1. 載入模型
    async function initModel() {
        try {
            session = await ort.InferenceSession.create('./best.onnx');
            statusDiv.innerText = "✅ 模型載入完成！請選擇圖片進行辨識。";
            imageInput.disabled = false;
        } catch (e) {
            statusDiv.innerText = "❌ 模型載入失敗，請確認 best.onnx 是否放在同目錄下。";
            console.error(e);
        }
    }

    // 2. 處理圖片上傳
    imageInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file || !session) return;

        const img = new Image();
        img.src = URL.createObjectURL(file);

        img.onload = async () => {
            canvas.width = img.width;
            canvas.height = img.height;
            ctx.drawImage(img, 0, 0);

            statusDiv.innerText = "⚡ 正在地端推理中...";
            
            const tensor = await preprocessImage(img);
            const results = await session.run({ images: tensor });
            
            // 執行 YOLOv8 / YOLO26 ONNX 後處理解析
            const boxes = postprocess(results, img.width, img.height, 0.45);
            
            // 清除上次畫布並重新繪製圖片
            ctx.drawImage(img, 0, 0);
            
            if (boxes.length === 0) {
                statusDiv.innerText = "⚠️ 未偵測到斑馬線！";
                drawBoxes([]); // 觸發未偵測到的文字提示
            } else {
                drawBoxes(boxes);
                statusDiv.innerText = `✅ 辨識完成！共找到 ${boxes.length} 個斑馬線。`;
            }
        };
    });

    // 圖片預處理：轉為 1x3x640x640 張量
    async function preprocessImage(img) {
        const tempCanvas = document.createElement('canvas');
        tempCanvas.width = 640;
        tempCanvas.height = 640;
        const tempCtx = tempCanvas.getContext('2d');
        tempCtx.drawImage(img, 0, 0, 640, 640);

        const imgData = tempCtx.getImageData(0, 0, 640, 640);
        const { data } = imgData;
        const red = [], green = [], blue = [];

        for (let i = 0; i < data.length; i += 4) {
            red.push(data[i] / 255.0);
            green.push(data[i + 1] / 255.0);
            blue.push(data[i + 2] / 255.0);
        }

        const float32Data = new Float32Array([...red, ...green, ...blue]);
        return new ort.Tensor('float32', float32Data, [1, 3, 640, 640]);
    }

    // 3. ONNX 輸出矩陣解析
    function postprocess(results, origW, origH, confThreshold) {
        const outputKey = Object.keys(results)[0];
        const data = results[outputKey].data; // Shape: [1, 5, 8400]
        const boxes = [];

        for (let i = 0; i < 8400; i++) {
            const score = data[4 * 8400 + i]; // 第 5 列為信心分數
            
            if (score >= confThreshold) {
                const cx = data[0 * 8400 + i];
                const cy = data[1 * 8400 + i];
                const w = data[2 * 8400 + i];
                const h = data[3 * 8400 + i];

                const x = (cx - w / 2) * (origW / 640);
                const y = (cy - h / 2) * (origH / 640);
                const bw = w * (origW / 640);
                const bh = h * (origH / 640);

                boxes.push({ x, y, w: bw, h: bh, score });
            }
        }

        return filterOverlapBoxes(boxes);
    }

    // NMS 重疊框過濾器
    function filterOverlapBoxes(boxes) {
        let candidateBoxes = [...boxes];
        candidateBoxes.sort((a, b) => b.score - a.score);
        const result = [];
        while (candidateBoxes.length > 0) {
            const current = candidateBoxes.shift();
            result.push(current);
            candidateBoxes = candidateBoxes.filter(box => {
                const iou = calculateIoU(current, box);
                return iou < 0.45;
            });
        }
        return result;
    }

    function calculateIoU(a, b) {
        const x1 = Math.max(a.x, b.x);
        const y1 = Math.max(a.y, b.y);
        const x2 = Math.min(a.x + a.w, b.x + b.w);
        const y2 = Math.min(a.y + a.h, b.y + b.h);
        const intersection = Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
        const union = (a.w * a.h) + (b.w * b.h) - intersection;
        return intersection / union;
    }

    // 4. 在 Canvas 上繪製邊框與顯示風險評估面板
  function drawBoxes(boxes) {
    const canvasEl = typeof canvas !== 'undefined' ? canvas : document.querySelector('canvas');
    if (!canvasEl) return;
    
    const ctxEl = canvasEl.getContext('2d');
    const imgHeight = canvasEl.height;
    
    let resultDiv = document.getElementById("risk-report");
    if (!resultDiv) {
        resultDiv = document.createElement("div");
        resultDiv.id = "risk-report";
        resultDiv.style.marginTop = "15px";
        resultDiv.style.padding = "15px";
        resultDiv.style.fontSize = "16px";
        resultDiv.style.fontFamily = "MingLiU, sans-serif";
        resultDiv.style.borderRadius = "8px";
        canvasEl.parentNode.appendChild(resultDiv);
    }

    if (!boxes || boxes.length === 0) {
        resultDiv.style.backgroundColor = "#f0f0f0";
        resultDiv.style.border = "1px solid #ccc";
        resultDiv.innerHTML = "<b>系統評估結果：</b>畫面中未偵測到斑馬線。";
        return;
    }

    // 💡 先檢查所有框框中，有沒有任何一個屬於「高風險」
    let hasHighRisk = false;
    boxes.forEach(box => {
        const boxBottom = box.y + box.h;
        const distToBottom = imgHeight - boxBottom;
        const boxHeightRatio = box.h / imgHeight;

        // 只要【離底端小於 18%】或【斑馬線佔據畫面高度超過 25%】，就認定為高風險
        if (distToBottom < imgHeight * 0.18 || boxHeightRatio > 0.25) {
            hasHighRisk = true;
        }
    });

    // 1. 先更新下方的整體系統報告面板
    const overallColor = hasHighRisk ? "#FF3333" : "#00FF66";
    const riskStatus = hasHighRisk ? "🔴 高風險（過於靠近路口轉角）" : "🟢 安全（退縮距離良好）";
    const suggestion = hasHighRisk 
        ? "⚠️ 改善建議：斑馬線過於貼近轉角，轉彎車輛易生視線死角，建議向後退縮 3~5 公尺。" 
        : "✅ 評估結果：該路口斑馬線佈局符合安全退縮規範。";

    resultDiv.style.backgroundColor = hasHighRisk ? "#FFE6E6" : "#E6FFE6";
    resultDiv.style.border = `2px solid ${overallColor}`;
    resultDiv.style.color = "#333333";
    resultDiv.innerHTML = `
        <h3 style="margin:0 0 8px 0;">🚦 靜態道路硬體危險度評估報告</h3>
        <p style="margin:4px 0;"><b>辨識目標：</b>斑馬線 (Crosswalk)</p>
        <p style="margin:4px 0;"><b>風險等級：</b><span style="color:${overallColor}; font-weight:bold;">${riskStatus}</span></p>
        <p style="margin:4px 0;"><b>系統說明：</b>${suggestion}</p>
    `;

    // 2. 逐一繪製每個斑馬線框框（個別顯示自己的顏色）
    boxes.forEach(box => {
        const boxBottom = box.y + box.h;
        const distToBottom = imgHeight - boxBottom;
        const boxHeightRatio = box.h / imgHeight;

        // 條件同步更新
        const isHighRisk = (distToBottom < imgHeight * 0.18) || (boxHeightRatio > 0.25);
        const color = isHighRisk ? "#FF3333" : "#00FF66";

        ctxEl.strokeStyle = color;
        ctxEl.lineWidth = 4;
        ctxEl.strokeRect(box.x, box.y, box.w, box.h);

        // 修正乘號 * 與語法
        const text = `crosswalk ${(box.score * 100).toFixed(1)}%`;
        ctxEl.font = "16px MingLiU, Arial";
        const textWidth = ctxEl.measureText(text).width;
        
        ctxEl.fillStyle = color;
        ctxEl.fillRect(box.x, box.y - 28, textWidth + 10, 28);
        ctxEl.fillStyle = "#FFFFFF";
        ctxEl.fillText(text, box.x + 5, box.y - 8);
    });
}

    // 啟動模型
    initModel();
</script>

</body>
</html>
