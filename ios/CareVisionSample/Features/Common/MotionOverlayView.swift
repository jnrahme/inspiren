import SwiftUI

struct MotionOverlayView: View {
  let overlay: MotionOverlayFrame
  var assumedAspectRatio: CGFloat = 16 / 9

  private let overlayColor = Color(red: 0.44, green: 0.99, blue: 0.66)

  var body: some View {
    GeometryReader { proxy in
      if overlay.isRenderable {
        let contentRect = aspectFitRect(
          for: proxy.size,
          aspectRatio: assumedAspectRatio
        )

        ZStack(alignment: .topLeading) {
          trailPath(in: contentRect)
            .stroke(overlayColor.opacity(0.18), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            .shadow(color: overlayColor.opacity(0.22), radius: 16)

          trailPath(in: contentRect)
            .stroke(overlayColor.opacity(trailOpacity), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

          skeletonPath(in: contentRect)
            .stroke(overlayColor.opacity(skeletonOpacity), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
            .shadow(color: overlayColor.opacity(0.18), radius: 10)

          if let personBox = overlay.personBox {
            let rect = rect(for: personBox, in: contentRect)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(overlayColor.opacity(0.78), lineWidth: 2.3)
              .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .fill(overlayColor.opacity(0.08))
              )
              .frame(width: rect.width, height: rect.height)
              .position(x: rect.midX, y: rect.midY)
              .shadow(color: overlayColor.opacity(0.18), radius: 12)
          }

          if let headPoint = overlay.trail.last {
            Circle()
              .fill(overlayColor.opacity(0.95))
              .frame(width: 10, height: 10)
              .position(point(for: headPoint, in: contentRect))
              .shadow(color: overlayColor.opacity(0.3), radius: 8)
          }

          Text("Vision overlay live")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(overlayColor.opacity(0.98))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
              Capsule(style: .continuous)
                .fill(Color.black.opacity(0.44))
            )
            .padding(14)
        }
      }
    }
    .allowsHitTesting(false)
  }

  private var trailOpacity: Double {
    min(0.92, 0.34 + overlay.motionScore * 0.7)
  }

  private var skeletonOpacity: Double {
    overlay.skeleton.isEmpty ? 0.0 : min(0.94, 0.42 + overlay.motionScore * 0.45)
  }

  private func aspectFitRect(for size: CGSize, aspectRatio: CGFloat) -> CGRect {
    let containerAspect = size.width / max(size.height, 1)

    if containerAspect > aspectRatio {
      let width = size.height * aspectRatio
      return CGRect(
        x: (size.width - width) / 2,
        y: 0,
        width: width,
        height: size.height
      )
    }

    let height = size.width / aspectRatio
    return CGRect(
      x: 0,
      y: (size.height - height) / 2,
      width: size.width,
      height: height
    )
  }

  private func point(for normalizedPoint: NormalizedPoint, in rect: CGRect) -> CGPoint {
    CGPoint(
      x: rect.minX + rect.width * normalizedPoint.x,
      y: rect.minY + rect.height * normalizedPoint.y
    )
  }

  private func rect(for normalizedRect: NormalizedRect, in rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX + rect.width * normalizedRect.x,
      y: rect.minY + rect.height * normalizedRect.y,
      width: rect.width * normalizedRect.width,
      height: rect.height * normalizedRect.height
    )
  }

  private func trailPath(in rect: CGRect) -> Path {
    var path = Path()
    guard overlay.trail.count > 1 else {
      return path
    }

    path.move(to: point(for: overlay.trail[0], in: rect))
    for pointValue in overlay.trail.dropFirst() {
      path.addLine(to: point(for: pointValue, in: rect))
    }
    return path
  }

  private func skeletonPath(in rect: CGRect) -> Path {
    var path = Path()

    for segment in overlay.skeleton {
      path.move(to: point(for: segment.from, in: rect))
      path.addLine(to: point(for: segment.to, in: rect))
    }

    return path
  }
}
