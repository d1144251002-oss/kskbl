index.html
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <title>交通號誌 AI 雲端辨識系統 (Roboflow Workflow)</title>
    <!-- 引入 Roboflow Inference SDK -->
    <script src="https://cdn.jsdelivr.net/npm/@roboflow/inference@latest/dist/roboflow.min.js"></script>
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
    <h2>🚦 斑馬線（Crosswalk）AI 雲端辨識系統</h2>
    <div id="status">✅ 系統準備就緒，請上傳圖片進行辨識。</div>
    <input type="file" id="imageInput" accept="image/*">
    <br>
    <canvas id="outputCanvas"></canvas>
</div>

<script>
    const statusDiv = document.getElementById('status');
    const imageInput = document.getElementById('imageInput');
    const canvas = document.getElementById('outputCanvas');
    const ctx = canvas.getContext('2d');

    // 1. 設定 Roboflow Workflow 參數
    const API_KEY = "O92bxnfSHT1SezxPFGCB";
    const WORKSPACE_NAME = "-ftvco";
    const WORKFLOW_ID = "001-mrbjp-1-rfdetr-small-t2-v001-mrbjp-1-rfdetr-small-t2-logic";

    // 2. 處理圖片上傳與 Workflow 推論
    imageInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const img = new Image();
        img.src = URL.createObjectURL(file);

        img.onload = async () => {
            // 初始化畫布尺寸
            canvas.width = img.width;
            canvas.height = img.height;
            ctx.drawImage(img, 0, 0);

            statusDiv.innerText = "⚡ 正在呼叫 Roboflow Workflow 雲端推論中...";
            imageInput.disabled = true;

            try {
                // 將圖片轉為 Base64 字串送至 Workflow
                const base64Image = await getBase64(file);
                
                const response = await fetch(`https://serverless.roboflow.com/workflows/${WORKSPACE_NAME}/${WORKFLOW_ID}?api_key=${API_KEY}`, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json"
                    },
                    body: JSON.stringify({
                        inputs: {
                            "image": {
                                "type": "base64",
                                "value": base64Image
                            }
                        }
                    })
                });

                const result = await response.json();
                
                // 解析 Workflow 輸出格式（嘗試提取預測框陣列）
                const boxes = parseWorkflowResults(result, img.width, img.height);
                
                // 清除上次畫布並重新繪製圖片
                ctx.drawImage(img, 0, 0);

                if (boxes.length === 0) {
                    statusDiv.innerText = "⚠️ 未偵測到斑馬線！";
                    drawBoxes([]);
                } else {
                    drawBoxes(boxes);
                    statusDiv.innerText = `✅ 辨識完成！共找到 ${boxes.length} 個斑馬線。`;
                }

            } catch (err) {
                console.error("Workflow 推論錯誤：", err);
                statusDiv.innerText = "❌ 辨識失敗，請檢查網路連線或 API Key 設定。";
            } finally {
                imageInput.disabled = false;
            }
        };
    });

    // 輔助函式：檔案轉 Base64
    function getBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.readAsDataURL(file);
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = error => reject(error);
        });
    }

    // 3. 解析 Roboflow Workflow 回傳的 JSON 資料結構
    function parseWorkflowResults(result, imgWidth, imgHeight) {
        const boxes = [];
        
        // 取得 workflow 輸出的結果點
        let predictions = [];
        if (result.outputs && Array.isArray(result.outputs)) {
            const firstOutput = result.outputs[0];
            // 搜尋輸出的 key 值
            for (let key in firstOutput) {
                if (firstOutput[key] && firstOutput[key].predictions) {
                    predictions = firstOutput[key].predictions;
                    break;
                } else if (Array.isArray(firstOutput[key])) {
                    predictions = firstOutput[key];
                    break;
                }
            }
        }

        predictions.forEach(pred => {
            if (pred.x !== undefined && pred.y !== undefined && pred.width !== undefined && pred.height !== undefined) {
                const bw = pred.width;
                const bh = pred.height;
                const x = pred.x - bw / 2;
                const y = pred.y - bh / 2;
                const score = pred.confidence || pred.score || 1.0;

                boxes.push({ x, y, w: bw, h: bh, score });
            }
        });

        return boxes;
    }

    // 4. 在 Canvas 上繪製邊框與顯示風險評估面板
    function drawBoxes(boxes) {
        const canvasEl = canvas;
        const ctxEl = ctx;
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

        // 檢查是否有任何一個區域屬於高風險
        let hasHighRisk = false;
        boxes.forEach(box => {
            const boxBottom = box.y + box.h;
            const distToBottom = imgHeight - boxBottom;
            const boxHeightRatio = box.h / imgHeight;

            if (distToBottom < imgHeight * 0.18 || boxHeightRatio > 0.25) {
                hasHighRisk = true;
            }
        });

        // 1. 更新系統評估報告
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

        // 2. 逐一繪製標記框
        boxes.forEach(box => {
            const boxBottom = box.y + box.h;
            const distToBottom = imgHeight - boxBottom;
            const boxHeightRatio = box.h / imgHeight;

            const isHighRisk = (distToBottom < imgHeight * 0.18) || (boxHeightRatio > 0.25);
            const color = isHighRisk ? "#FF3333" : "#00FF66";

            ctxEl.strokeStyle = color;
            ctxEl.lineWidth = 4;
            ctxEl.strokeRect(box.x, box.y, box.w, box.h);

            const text = `crosswalk ${(box.score * 100).toFixed(1)}%`;
            ctxEl.font = "16px MingLiU, Arial";
            const textWidth = ctxEl.measureText(text).width;
            
            ctxEl.fillStyle = color;
            ctxEl.fillRect(box.x, box.y - 28, textWidth + 10, 28);
            ctxEl.fillStyle = "#FFFFFF";
            ctxEl.fillText(text, box.x + 5, box.y - 8);
        });
    }
</script>

</body>
</html>
