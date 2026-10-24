#pragma once

#include <QBrush>
#include <QColor>
#include <QLinearGradient>
#include <QList>
#include <QPainterPath>
#include <QPointF>
#include <QQuickPaintedItem>
#include <QRectF>
#include <QString>
#include <QVariantList>
#include <QVector>
#include <qqmlregistration.h>

#include <array>

class CavaSpectrumPainter : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QList<qreal> points READ points WRITE setPoints NOTIFY pointsChanged)
    Q_PROPERTY(QString visualizerType READ visualizerType WRITE setVisualizerType NOTIFY visualizerTypeChanged)
    Q_PROPERTY(qreal normalizationCeiling READ normalizationCeiling WRITE setNormalizationCeiling NOTIFY normalizationCeilingChanged)
    Q_PROPERTY(qreal fillRatio READ fillRatio WRITE setFillRatio NOTIFY fillRatioChanged)
    Q_PROPERTY(qreal spectrumOpacity READ spectrumOpacity WRITE setSpectrumOpacity NOTIFY spectrumOpacityChanged)
    Q_PROPERTY(QColor spectrumColor READ spectrumColor WRITE setSpectrumColor NOTIFY spectrumColorChanged)
    Q_PROPERTY(QVariantList spectrumColors READ spectrumColors WRITE setSpectrumColors NOTIFY spectrumColorsChanged)
    Q_PROPERTY(qreal sampleStartRatio READ sampleStartRatio WRITE setSampleStartRatio NOTIFY sampleStartRatioChanged)
    Q_PROPERTY(qreal sampleEndRatio READ sampleEndRatio WRITE setSampleEndRatio NOTIFY sampleEndRatioChanged)
    Q_PROPERTY(bool reverseFrequency READ reverseFrequency WRITE setReverseFrequency NOTIFY reverseFrequencyChanged)
    Q_PROPERTY(qreal pixelsPerBar READ pixelsPerBar WRITE setPixelsPerBar NOTIFY pixelsPerBarChanged)
    Q_PROPERTY(qreal barSpacing READ barSpacing WRITE setBarSpacing NOTIFY barSpacingChanged)
    Q_PROPERTY(qreal barRadius READ barRadius WRITE setBarRadius NOTIFY barRadiusChanged)
    Q_PROPERTY(qreal barMinHeight READ barMinHeight WRITE setBarMinHeight NOTIFY barMinHeightChanged)
    Q_PROPERTY(QString barsOrigin READ barsOrigin WRITE setBarsOrigin NOTIFY barsOriginChanged)
    Q_PROPERTY(int smoothing READ smoothing WRITE setSmoothing NOTIFY smoothingChanged)
    Q_PROPERTY(QString waveMode READ waveMode WRITE setWaveMode NOTIFY waveModeChanged)
    Q_PROPERTY(qreal lineWidth READ lineWidth WRITE setLineWidth NOTIFY lineWidthChanged)
    Q_PROPERTY(qreal edgeInset READ edgeInset WRITE setEdgeInset NOTIFY edgeInsetChanged)
    Q_PROPERTY(qreal leftRadius READ leftRadius WRITE setLeftRadius NOTIFY leftRadiusChanged)
    Q_PROPERTY(qreal rightRadius READ rightRadius WRITE setRightRadius NOTIFY rightRadiusChanged)
    Q_PROPERTY(qreal topLeftRadius READ topLeftRadius WRITE setTopLeftRadius NOTIFY topLeftRadiusChanged)
    Q_PROPERTY(qreal topRightRadius READ topRightRadius WRITE setTopRightRadius NOTIFY topRightRadiusChanged)
    Q_PROPERTY(qreal bottomLeftRadius READ bottomLeftRadius WRITE setBottomLeftRadius NOTIFY bottomLeftRadiusChanged)
    Q_PROPERTY(qreal bottomRightRadius READ bottomRightRadius WRITE setBottomRightRadius NOTIFY bottomRightRadiusChanged)
    Q_PROPERTY(qreal edgeSoftness READ edgeSoftness WRITE setEdgeSoftness NOTIFY edgeSoftnessChanged)
    Q_PROPERTY(QString frequencyProfile READ frequencyProfile WRITE setFrequencyProfile NOTIFY frequencyProfileChanged)
    Q_PROPERTY(qreal accentStrength READ accentStrength WRITE setAccentStrength NOTIFY accentStrengthChanged)
    Q_PROPERTY(bool mirroredStereo READ mirroredStereo WRITE setMirroredStereo NOTIFY mirroredStereoChanged)
    Q_PROPERTY(qreal startOpacity READ startOpacity WRITE setStartOpacity NOTIFY startOpacityChanged)
    Q_PROPERTY(qreal endOpacity READ endOpacity WRITE setEndOpacity NOTIFY endOpacityChanged)
    Q_PROPERTY(qreal startTaper READ startTaper WRITE setStartTaper NOTIFY startTaperChanged)
    Q_PROPERTY(qreal endTaper READ endTaper WRITE setEndTaper NOTIFY endTaperChanged)
    Q_PROPERTY(QVariantList clipSegments READ clipSegments WRITE setClipSegments NOTIFY clipSegmentsChanged)

public:
    explicit CavaSpectrumPainter(QQuickItem* parent = nullptr);

    const QList<qreal>& points() const { return m_points; }
    void setPoints(const QList<qreal>& points);
    const QString& visualizerType() const { return m_visualizerType; }
    void setVisualizerType(const QString& type);
    qreal normalizationCeiling() const { return m_normalizationCeiling; }
    void setNormalizationCeiling(qreal ceiling);
    qreal fillRatio() const { return m_fillRatio; }
    void setFillRatio(qreal ratio);
    qreal spectrumOpacity() const { return m_spectrumOpacity; }
    void setSpectrumOpacity(qreal opacity);
    QColor spectrumColor() const { return m_spectrumColor; }
    void setSpectrumColor(const QColor& color);
    const QVariantList& spectrumColors() const { return m_spectrumColors; }
    void setSpectrumColors(const QVariantList& colors);
    qreal sampleStartRatio() const { return m_sampleStartRatio; }
    void setSampleStartRatio(qreal ratio);
    qreal sampleEndRatio() const { return m_sampleEndRatio; }
    void setSampleEndRatio(qreal ratio);
    bool reverseFrequency() const { return m_reverseFrequency; }
    void setReverseFrequency(bool reverse);
    qreal pixelsPerBar() const { return m_pixelsPerBar; }
    void setPixelsPerBar(qreal pixels);
    qreal barSpacing() const { return m_barSpacing; }
    void setBarSpacing(qreal spacing);
    qreal barRadius() const { return m_barRadius; }
    void setBarRadius(qreal radius);
    qreal barMinHeight() const { return m_barMinHeight; }
    void setBarMinHeight(qreal height);
    const QString& barsOrigin() const { return m_barsOrigin; }
    void setBarsOrigin(const QString& origin);
    int smoothing() const { return m_smoothing; }
    void setSmoothing(int smoothing);
    const QString& waveMode() const { return m_waveMode; }
    void setWaveMode(const QString& mode);
    qreal lineWidth() const { return m_lineWidth; }
    void setLineWidth(qreal width);
    qreal edgeInset() const { return m_edgeInset; }
    void setEdgeInset(qreal inset);
    qreal leftRadius() const { return m_leftRadius; }
    void setLeftRadius(qreal radius);
    qreal rightRadius() const { return m_rightRadius; }
    void setRightRadius(qreal radius);
    qreal topLeftRadius() const { return m_topLeftRadius; }
    void setTopLeftRadius(qreal radius);
    qreal topRightRadius() const { return m_topRightRadius; }
    void setTopRightRadius(qreal radius);
    qreal bottomLeftRadius() const { return m_bottomLeftRadius; }
    void setBottomLeftRadius(qreal radius);
    qreal bottomRightRadius() const { return m_bottomRightRadius; }
    void setBottomRightRadius(qreal radius);
    qreal edgeSoftness() const { return m_edgeSoftness; }
    void setEdgeSoftness(qreal softness);
    const QString& frequencyProfile() const { return m_frequencyProfile; }
    void setFrequencyProfile(const QString& profile);
    qreal accentStrength() const { return m_accentStrength; }
    void setAccentStrength(qreal strength);
    bool mirroredStereo() const { return m_mirroredStereo; }
    void setMirroredStereo(bool mirrored);
    qreal startOpacity() const { return m_startOpacity; }
    void setStartOpacity(qreal opacity);
    qreal endOpacity() const { return m_endOpacity; }
    void setEndOpacity(qreal opacity);
    qreal startTaper() const { return m_startTaper; }
    void setStartTaper(qreal taper);
    qreal endTaper() const { return m_endTaper; }
    void setEndTaper(qreal taper);
    const QVariantList& clipSegments() const { return m_clipSegments; }
    void setClipSegments(const QVariantList& segments);

    void paint(QPainter* painter) override;

signals:
    void pointsChanged();
    void visualizerTypeChanged();
    void normalizationCeilingChanged();
    void fillRatioChanged();
    void spectrumOpacityChanged();
    void spectrumColorChanged();
    void spectrumColorsChanged();
    void sampleStartRatioChanged();
    void sampleEndRatioChanged();
    void reverseFrequencyChanged();
    void pixelsPerBarChanged();
    void barSpacingChanged();
    void barRadiusChanged();
    void barMinHeightChanged();
    void barsOriginChanged();
    void smoothingChanged();
    void waveModeChanged();
    void lineWidthChanged();
    void edgeInsetChanged();
    void leftRadiusChanged();
    void rightRadiusChanged();
    void topLeftRadiusChanged();
    void topRightRadiusChanged();
    void bottomLeftRadiusChanged();
    void bottomRightRadiusChanged();
    void edgeSoftnessChanged();
    void frequencyProfileChanged();
    void accentStrengthChanged();
    void mirroredStereoChanged();
    void startOpacityChanged();
    void endOpacityChanged();
    void startTaperChanged();
    void endTaperChanged();
    void clipSegmentsChanged();

protected:
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private:
    struct ClipSegment {
        QRectF rect;
        std::array<qreal, 4> radii{};
    };

    using ChangeSignal = void (CavaSpectrumPainter::*)();

    void notifyAndUpdate(ChangeSignal signal);
    void makePalette();
    QColor colorAt(qreal position) const;
    QLinearGradient horizontalGradient(qreal x0, qreal x1, qreal alphaScale) const;
    void selectedPoints();
    qreal profileWeight(qreal position) const;
    void applyFrequencyProfile();
    QList<qreal>& frequencySmooth();
    void barLevels(const QList<qreal>& source, int count);
    void waveLevels(const QList<qreal>& source, int count);
    void makeCornerRadii(qreal width, qreal height);
    static qreal smoothstep(qreal value);
    void makeEdgeTapers();
    qreal edgeMorphFactor(qreal x, qreal x0, qreal x1) const;
    qreal cornerInset(qreal x, qreal radius, bool fromLeft) const;
    std::array<qreal, 2> surfaceBounds(qreal x) const;
    std::array<qreal, 2> peakBounds(const std::array<qreal, 2>& surface) const;
    static void appendRoundedClip(QPainterPath& path, qreal x, qreal y, qreal width,
                                  qreal height, const std::array<qreal, 4>& radii);
    void clipSurface();
    qreal alphaAt(qreal x) const;
    static void roundedRect(QPainterPath& path, qreal x, qreal y, qreal width,
                            qreal height, qreal radius);
    void paintBars(QPainter* painter, const QList<qreal>& source, qreal x0, qreal x1);
    static void traceSmooth(QPainterPath& path, const QVector<QPointF>& coordinates);
    void paintWave(QPainter* painter, const QList<qreal>& source, qreal x0, qreal x1);
    void rebuildGradient();
    void rebuildClipSegments();
    void rebuildGeometryCaches(qreal width, qreal height);

    QList<qreal> m_points;
    QString m_visualizerType{QStringLiteral("bars")};
    qreal m_normalizationCeiling = 1000.0;
    qreal m_fillRatio = 0.6;
    qreal m_spectrumOpacity = 0.35;
    QColor m_spectrumColor{Qt::white};
    QVariantList m_spectrumColors;
    qreal m_sampleStartRatio = 0.0;
    qreal m_sampleEndRatio = 1.0;
    bool m_reverseFrequency = false;
    qreal m_pixelsPerBar = 12.0;
    qreal m_barSpacing = 2.0;
    qreal m_barRadius = 2.0;
    qreal m_barMinHeight = 1.0;
    QString m_barsOrigin{QStringLiteral("bottom")};
    int m_smoothing = 2;
    QString m_waveMode{QStringLiteral("fill")};
    qreal m_lineWidth = 2.0;
    qreal m_edgeInset = 0.0;
    qreal m_leftRadius = 0.0;
    qreal m_rightRadius = 0.0;
    qreal m_topLeftRadius = -1.0;
    qreal m_topRightRadius = -1.0;
    qreal m_bottomLeftRadius = -1.0;
    qreal m_bottomRightRadius = -1.0;
    qreal m_edgeSoftness = 0.28;
    QString m_frequencyProfile{QStringLiteral("flat")};
    qreal m_accentStrength = 0.7;
    bool m_mirroredStereo = true;
    qreal m_startOpacity = 1.0;
    qreal m_endOpacity = 1.0;
    qreal m_startTaper = -1.0;
    qreal m_endTaper = -1.0;
    QVariantList m_clipSegments;

    qreal m_cachedWidth = 0.0;
    qreal m_cachedHeight = 0.0;
    qreal m_gradientX0 = 0.0;
    qreal m_gradientX1 = 1.0;
    QVector<QColor> m_palette;
    std::array<qreal, 4> m_cornerRadii{};
    std::array<qreal, 2> m_edgeTapers{};
    QVector<ClipSegment> m_parsedClipSegments;
    QBrush m_gradientBrush;
    QPainterPath m_clipPath;
    QPainterPath m_shapePath;
    QPainterPath m_wavePath;
    QList<qreal> m_selected;
    QList<qreal> m_smoothed;
    QList<qreal> m_levels;
    QVector<QPointF> m_primary;
    QVector<QPointF> m_secondary;
    QVector<QPointF> m_baseline;
};
