import QtQuick
import stage.modules.common
import stage.services

Item {
    id: root

    property int wCode: (Weather.data && Weather.data.wCode !== undefined) ? Weather.data.wCode : 113
    property bool isNight: {
        if (DateTime.clock && DateTime.clock.date) {
            const hour = DateTime.clock.date.getHours();
            return hour >= 18 || hour < 6;
        }
        return false;
    }
    property color dotColor: WidgetColorScheme.textColorOnBg
    property real iconSize: Math.min(width, height)

    function getDotMatrix() {
        const code = root.wCode;
        const night = root.isNight;
        if (code === 113)
            return night ? getMoonDots() : getSunDots();
        else if (code === 116)
            return night ? getCloudMoonDots() : getCloudSunDots();
        else if (code === 143 || code === 248)
            return getFogDots();
        else if (code === 176 || code === 266 || code === 296 || code === 302 || code === 308 || code === 353)
            return getRainDots();
        else if (code === 200 || code === 386 || code === 389)
            return getThunderDots();
        else if (code === 284 || code === 311 || code === 326 || code === 332 || code === 338 || code === 368)
            return getSnowDots();
        return getCloudDots();
    }

    // --- 1. Cloud Dots (Exact NothingOS Dot Cloud from Image 1) ---
    function getCloudDots() {
        // x=0: 2 dots
        // x=1: 4 dots
        // x=2: 6 dots
        // x=3: 6 dots
        // x=4: 4 dots
        // x=5: 5 dots
        // x=6: 8 dots
        // x=7: 8 dots
        // x=8: 6 dots
        // x=9: 5 dots
        // x=10: 3 dots
        // x=11: 2 dots

        const dots = [];
        // Column heights mapping (x: 0..11, y: 0..7)
        const cols = [[1, 2], [0, 1, 2, 3], [0, 1, 2, 3, 4, 5], [0, 1, 2, 3, 4, 5], [0, 1, 2, 3], [0, 1, 2, 3, 4], [0, 1, 2, 3, 4, 5, 6, 7], [0, 1, 2, 3, 4, 5, 6, 7], [0, 1, 2, 3, 4, 5], [0, 1, 2, 3, 4], [0, 1, 2], [0, 1]];
        for (let x = 0; x < cols.length; x++) {
            const rows = cols[x];
            for (let r = 0; r < rows.length; r++) {
                dots.push({
                    "x": x,
                    "y": rows[r]
                });
            }
        }
        return dots;
    }

    // --- 2. Sun Dots (Clear Day) ---
    function getSunDots() {
        const dots = [];
        // Core 3x3
        for (let x = 3; x <= 5; x++) {
            for (let y = 3; y <= 5; y++) {
                dots.push({
                    "x": x,
                    "y": y
                });
            }
        }
        // Radiating rays around the core
        dots.push({
            "x": 4,
            "y": 7
        });
        // Top
        dots.push({
            "x": 4,
            "y": 1
        });
        // Bottom
        dots.push({
            "x": 1,
            "y": 4
        });
        // Left
        dots.push({
            "x": 7,
            "y": 4
        });
        // Right
        dots.push({
            "x": 2,
            "y": 6
        });
        // Top-Left
        dots.push({
            "x": 6,
            "y": 6
        });
        // Top-Right
        dots.push({
            "x": 2,
            "y": 2
        });
        // Bottom-Left
        dots.push({
            "x": 6,
            "y": 2
        });
        // Bottom-Right
        return dots;
    }

    // --- 3. Moon Crescent + Star Dots (Refined Crescent Moon) ---
    function getMoonDots() {
        const dots = [];
        // Slender, elegant crescent moon curve
        const moonRows = [{
            "y": 7,
            "xs": [2, 3]
        }, {
            "y": 6,
            "xs": [1, 2, 3]
        }, {
            "y": 5,
            "xs": [0, 1, 2]
        }, {
            "y": 4,
            "xs": [0, 1, 2]
        }, {
            "y": 3,
            "xs": [0, 1, 2]
        }, {
            "y": 2,
            "xs": [1, 2, 3]
        }, {
            "y": 1,
            "xs": [2, 3, 4]
        }, {
            "y": 0,
            "xs": [3, 4]
        }];
        for (let i = 0; i < moonRows.length; i++) {
            const row = moonRows[i];
            for (let j = 0; j < row.xs.length; j++) {
                dots.push({
                    "x": row.xs[j],
                    "y": row.y
                });
            }
        }
        // 4-Dot Star at top right
        dots.push({
            "x": 7,
            "y": 7
        });
        dots.push({
            "x": 7,
            "y": 5
        });
        dots.push({
            "x": 6,
            "y": 6
        });
        dots.push({
            "x": 8,
            "y": 6
        });
        return dots;
    }

    // --- 4. Cloud + Sun Rays (Refined Sun Arch over Cloud) ---
    function getCloudSunDots() {
        // x=0
        // x=1
        // x=2
        // x=3
        // x=4
        // x=5
        // x=6
        // x=7
        // x=8
        // x=9
        // x=10

        const dots = [];
        // Harmonious 5-dot sun arch centered over cloud
        dots.push({
            "x": 1,
            "y": 5
        });
        dots.push({
            "x": 2,
            "y": 7
        });
        dots.push({
            "x": 4,
            "y": 8
        });
        dots.push({
            "x": 6,
            "y": 7
        });
        dots.push({
            "x": 7,
            "y": 5
        });
        // Cloud body below (y: 0..4)
        const cols = [[], [1, 2], [0, 1, 2, 3], [0, 1, 2, 3, 4], [0, 1, 2, 3, 4], [0, 1, 2, 3], [0, 1, 2, 3, 4], [0, 1, 2, 3, 4], [0, 1, 2, 3], [0, 1, 2], [1]];
        for (let x = 0; x < cols.length; x++) {
            const rows = cols[x];
            for (let r = 0; r < rows.length; r++) {
                dots.push({
                    "x": x,
                    "y": rows[r]
                });
            }
        }
        return dots;
    }

    // --- 5. Cloud + Moon (Partly Cloudy Night) ---
    function getCloudMoonDots() {
        // x=0
        // x=1
        // x=2
        // x=3
        // x=4
        // x=5
        // x=6
        // x=7
        // x=8
        // x=9

        const dots = [];
        // Crescent moon at top-right above cloud
        const moonCoords = [{
            "x": 7,
            "y": 8
        }, {
            "x": 8,
            "y": 8
        }, {
            "x": 6,
            "y": 7
        }, {
            "x": 7,
            "y": 7
        }, {
            "x": 6,
            "y": 6
        }, {
            "x": 7,
            "y": 6
        }, {
            "x": 7,
            "y": 5
        }, {
            "x": 8,
            "y": 5
        }];
        for (let i = 0; i < moonCoords.length; i++) {
            dots.push(moonCoords[i]);
        }
        dots.push({
            "x": 10,
            "y": 8
        }); // Star dot
        // Cloud body
        const cols = [[], [1, 2], [0, 1, 2, 3], [0, 1, 2, 3, 4], [0, 1, 2, 3, 4], [0, 1, 2, 3], [0, 1, 2, 3, 4], [0, 1, 2, 3], [0, 1, 2], [1]];
        for (let x = 0; x < cols.length; x++) {
            const rows = cols[x];
            for (let r = 0; r < rows.length; r++) {
                dots.push({
                    "x": x,
                    "y": rows[r]
                });
            }
        }
        return dots;
    }

    // --- 6. Cloud + Rain Drops (Image 4) ---
    function getRainDots() {
        const dots = [];
        // Cloud on top (y: 3..10)
        const cloudDots = getCloudDots();
        for (let i = 0; i < cloudDots.length; i++) {
            dots.push({
                "x": cloudDots[i].x,
                "y": cloudDots[i].y + 3
            });
        }
        // 3 diagonal rain drops below (y: 0, 1)
        dots.push({
            "x": 2,
            "y": 1
        }, {
            "x": 3,
            "y": 0
        });
        // Left drop
        dots.push({
            "x": 5,
            "y": 1
        }, {
            "x": 6,
            "y": 0
        });
        // Mid drop
        dots.push({
            "x": 8,
            "y": 1
        }, {
            "x": 9,
            "y": 0
        });
        // Right drop
        return dots;
    }

    // --- 7. Thunderstorm ---
    function getThunderDots() {
        const dots = [];
        const cloudDots = getCloudDots();
        for (let i = 0; i < cloudDots.length; i++) {
            dots.push({
                "x": cloudDots[i].x,
                "y": cloudDots[i].y + 4
            });
        }
        // Zigzag lightning bolt
        dots.push({
            "x": 6,
            "y": 4
        }, {
            "x": 5,
            "y": 3
        }, {
            "x": 4,
            "y": 2
        }, {
            "x": 5,
            "y": 2
        }, {
            "x": 4,
            "y": 1
        }, {
            "x": 3,
            "y": 0
        });
        return dots;
    }

    // --- 8. Snow ---
    function getSnowDots() {
        const dots = [];
        const cloudDots = getCloudDots();
        for (let i = 0; i < cloudDots.length; i++) {
            dots.push({
                "x": cloudDots[i].x,
                "y": cloudDots[i].y + 3
            });
        }
        // Snow flakes / dots below
        dots.push({
            "x": 2,
            "y": 1
        }, {
            "x": 4,
            "y": 0
        }, {
            "x": 6,
            "y": 1
        }, {
            "x": 8,
            "y": 0
        }, {
            "x": 10,
            "y": 1
        });
        return dots;
    }

    // --- 9. Fog / Mist ---
    function getFogDots() {
        const dots = [];
        // 3 horizontal dot bars
        for (let x = 2; x <= 9; x++) dots.push({
            "x": x,
            "y": 5
        })
        for (let x = 1; x <= 10; x++) dots.push({
            "x": x,
            "y": 3
        })
        for (let x = 2; x <= 9; x++) dots.push({
            "x": x,
            "y": 1
        })
        return dots;
    }

    implicitWidth: 120
    implicitHeight: 120
    onWCodeChanged: canvas.requestPaint()
    onIsNightChanged: canvas.requestPaint()
    onDotColorChanged: canvas.requestPaint()
    onIconSizeChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            const dots = root.getDotMatrix();
            if (!dots || dots.length === 0)
                return ;

            // Calculate grid bounds
            let minX = Infinity, maxX = -Infinity;
            let minY = Infinity, maxY = -Infinity;
            for (let i = 0; i < dots.length; i++) {
                const pt = dots[i];
                if (pt.x < minX)
                    minX = pt.x;

                if (pt.x > maxX)
                    maxX = pt.x;

                if (pt.y < minY)
                    minY = pt.y;

                if (pt.y > maxY)
                    maxY = pt.y;

            }
            const gridW = maxX - minX + 1;
            const gridH = maxY - minY + 1;
            const maxSpan = Math.max(gridW, gridH, 1);
            // Calculate scaling so grid fits nicely in iconSize
            const padding = 14;
            const availSize = Math.max(10, root.iconSize - padding * 2);
            const spacing = availSize / maxSpan;
            const dotRadius = Math.max(1.5, spacing * 0.4);
            const centerX = canvas.width / 2;
            const centerY = canvas.height / 2;
            const midGridX = (minX + maxX) / 2;
            const midGridY = (minY + maxY) / 2;
            ctx.fillStyle = root.dotColor.toString();
            for (let i = 0; i < dots.length; i++) {
                const pt = dots[i];
                const px = centerX + (pt.x - midGridX) * spacing;
                const py = centerY - (pt.y - midGridY) * spacing;
                ctx.beginPath();
                ctx.arc(px, py, dotRadius, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

}
