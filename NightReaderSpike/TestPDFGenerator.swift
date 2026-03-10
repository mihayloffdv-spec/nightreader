import UIKit
import PDFKit

struct TestPDFGenerator {

    static func generateAllTestPDFs() -> [String: PDFDocument] {
        var pdfs: [String: PDFDocument] = [:]
        if let doc = generateTextOnly() { pdfs["Text Only"] = doc }
        if let doc = generateTextWithImages() { pdfs["Text + Images"] = doc }
        if let doc = generateColoredDiagrams() { pdfs["Colored Diagrams"] = doc }
        return pdfs
    }

    // MARK: - 1. Text Only (5 pages of Lorem Ipsum)

    static func generateTextOnly() -> PDFDocument? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 50

        let loremIpsum = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

        Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt.

        Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur?

        At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum deleniti atque corrupti quos dolores et quas molestias excepturi sint occaecati cupiditate non provident, similique sunt in culpa qui officia deserunt mollitia animi, id est laborum et dolorum fuga.

        Et harum quidem rerum facilis est et expedita distinctio. Nam libero tempore, cum soluta nobis est eligendi optio cumque nihil impedit quo minus id quod maxime placeat facere possimus, omnis voluptas assumenda est, omnis dolor repellendus.
        """

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            let textFont = UIFont.systemFont(ofSize: 14)
            let titleFont = UIFont.boldSystemFont(ofSize: 22)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 12

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]

            for page in 1...5 {
                context.beginPage()
                let textRect = CGRect(
                    x: margin, y: margin,
                    width: pageRect.width - margin * 2,
                    height: pageRect.height - margin * 2
                )

                let title = "Chapter \(page): Lorem Ipsum"
                title.draw(in: CGRect(x: margin, y: margin, width: textRect.width, height: 30),
                           withAttributes: titleAttributes)

                let bodyRect = CGRect(
                    x: margin, y: margin + 40,
                    width: textRect.width,
                    height: textRect.height - 40
                )
                loremIpsum.draw(in: bodyRect, withAttributes: textAttributes)

                // Page number
                let pageNum = "Page \(page)"
                let pageNumSize = pageNum.size(withAttributes: textAttributes)
                pageNum.draw(
                    at: CGPoint(x: pageRect.width / 2 - pageNumSize.width / 2,
                                y: pageRect.height - margin + 10),
                    withAttributes: textAttributes
                )
            }
        }

        return PDFDocument(data: data)
    }

    // MARK: - 2. Text with Images (colored rectangles as placeholders)

    static func generateTextWithImages() -> PDFDocument? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 50

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            let textFont = UIFont.systemFont(ofSize: 13)
            let titleFont = UIFont.boldSystemFont(ofSize: 20)
            let captionFont = UIFont.italicSystemFont(ofSize: 11)

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: UIColor.black
            ]
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            let captionAttributes: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.darkGray
            ]

            let sampleText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."

            let imageColors: [UIColor] = [
                UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1),   // Blue
                UIColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1),   // Red
                UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1),   // Green
                UIColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 1),   // Orange
                UIColor(red: 0.6, green: 0.3, blue: 0.7, alpha: 1),   // Purple
            ]

            for page in 0..<3 {
                context.beginPage()

                let title = "Article with Images — Page \(page + 1)"
                title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)

                var yOffset: CGFloat = margin + 35

                // Text block
                sampleText.draw(
                    in: CGRect(x: margin, y: yOffset, width: pageRect.width - margin * 2, height: 80),
                    withAttributes: textAttributes
                )
                yOffset += 90

                // Image placeholder 1 (large)
                let imgRect1 = CGRect(x: margin, y: yOffset, width: pageRect.width - margin * 2, height: 200)
                let color1 = imageColors[page % imageColors.count]
                color1.setFill()
                UIRectFill(imgRect1)
                // Draw a gradient-like pattern inside
                let lighterColor = color1.withAlphaComponent(0.5)
                lighterColor.setFill()
                UIRectFill(CGRect(x: imgRect1.midX, y: imgRect1.minY, width: imgRect1.width / 2, height: imgRect1.height))
                // Label
                let imgLabel = "Figure \(page * 2 + 1): Sample Image"
                imgLabel.draw(
                    at: CGPoint(x: imgRect1.midX - 60, y: imgRect1.midY - 10),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.white]
                )
                yOffset += 210
                "Fig. \(page * 2 + 1) — Placeholder image with gradient".draw(
                    at: CGPoint(x: margin, y: yOffset),
                    withAttributes: captionAttributes
                )
                yOffset += 30

                // More text
                sampleText.draw(
                    in: CGRect(x: margin, y: yOffset, width: pageRect.width - margin * 2, height: 80),
                    withAttributes: textAttributes
                )
                yOffset += 90

                // Image placeholder 2 (smaller, side by side)
                let smallWidth = (pageRect.width - margin * 3) / 2
                let color2 = imageColors[(page + 1) % imageColors.count]
                let color3 = imageColors[(page + 2) % imageColors.count]

                color2.setFill()
                UIRectFill(CGRect(x: margin, y: yOffset, width: smallWidth, height: 150))
                color3.setFill()
                UIRectFill(CGRect(x: margin * 2 + smallWidth, y: yOffset, width: smallWidth, height: 150))

                "A".draw(at: CGPoint(x: margin + smallWidth / 2 - 5, y: yOffset + 65),
                         withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])
                "B".draw(at: CGPoint(x: margin * 2 + smallWidth + smallWidth / 2 - 5, y: yOffset + 65),
                         withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])

                yOffset += 160
                "Fig. \(page * 2 + 2) — Comparison: variant A vs variant B".draw(
                    at: CGPoint(x: margin, y: yOffset),
                    withAttributes: captionAttributes
                )
            }
        }

        return PDFDocument(data: data)
    }

    // MARK: - 3. Colored Diagrams (tables, colored text, charts)

    static func generateColoredDiagrams() -> PDFDocument? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 50

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in

            // Page 1: Colored text and headers
            context.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1)
            ]
            "Data Report — Q4 2025".draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttrs)

            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
            ]
            "Generated for NightReader Spike Test".draw(at: CGPoint(x: margin, y: margin + 35), withAttributes: subtitleAttrs)

            // Colored text sections
            let colors: [(UIColor, String)] = [
                (UIColor.systemRed, "Critical: System load exceeded threshold on 3 occasions."),
                (UIColor.systemOrange, "Warning: Memory usage peaked at 87% during batch processing."),
                (UIColor.systemGreen, "Success: All 142 test cases passed in the latest build."),
                (UIColor.systemBlue, "Info: New deployment scheduled for next maintenance window."),
                (UIColor.systemPurple, "Note: Feature flags updated for A/B testing cohort."),
            ]

            var y: CGFloat = margin + 80
            for (color, text) in colors {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: color
                ]
                // Colored bullet
                color.setFill()
                UIRectFill(CGRect(x: margin, y: y + 3, width: 10, height: 10))
                text.draw(in: CGRect(x: margin + 18, y: y, width: pageRect.width - margin * 2 - 18, height: 40),
                          withAttributes: attrs)
                y += 35
            }

            // Table
            y += 20
            drawTable(at: CGPoint(x: margin, y: y),
                      width: pageRect.width - margin * 2,
                      headers: ["Metric", "Q3", "Q4", "Change"],
                      rows: [
                        ["Users", "12,450", "15,820", "+27%"],
                        ["Revenue", "$84K", "$102K", "+21%"],
                        ["Latency", "45ms", "38ms", "-16%"],
                        ["Errors", "0.3%", "0.1%", "-67%"],
                        ["Uptime", "99.9%", "99.95%", "+0.05%"],
                      ],
                      in: context)

            // Page 2: Bar chart and pie-like diagram
            context.beginPage()
            "Performance Overview".draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttrs)

            // Simple bar chart
            let barColors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemRed, .systemPurple, .systemTeal]
            let barValues: [(String, CGFloat)] = [("Jan", 0.6), ("Feb", 0.75), ("Mar", 0.5), ("Apr", 0.9), ("May", 0.85), ("Jun", 0.95)]
            let chartX: CGFloat = margin
            let chartY: CGFloat = margin + 60
            let chartWidth: CGFloat = pageRect.width - margin * 2
            let chartHeight: CGFloat = 200
            let barWidth: CGFloat = chartWidth / CGFloat(barValues.count) - 10

            // Chart background
            UIColor(white: 0.95, alpha: 1).setFill()
            UIRectFill(CGRect(x: chartX, y: chartY, width: chartWidth, height: chartHeight))

            // Grid lines
            UIColor(white: 0.8, alpha: 1).setStroke()
            for i in 0...4 {
                let lineY = chartY + chartHeight * CGFloat(i) / 4
                let path = UIBezierPath()
                path.move(to: CGPoint(x: chartX, y: lineY))
                path.addLine(to: CGPoint(x: chartX + chartWidth, y: lineY))
                path.lineWidth = 0.5
                path.stroke()
            }

            // Bars
            for (i, (label, value)) in barValues.enumerated() {
                let x = chartX + CGFloat(i) * (barWidth + 10) + 5
                let barHeight = chartHeight * value
                let barRect = CGRect(x: x, y: chartY + chartHeight - barHeight, width: barWidth, height: barHeight)
                barColors[i % barColors.count].setFill()
                UIRectFill(barRect)

                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.black
                ]
                label.draw(at: CGPoint(x: x + barWidth / 2 - 10, y: chartY + chartHeight + 5), withAttributes: labelAttrs)

                let valueStr = "\(Int(value * 100))%"
                valueStr.draw(at: CGPoint(x: x + barWidth / 2 - 12, y: chartY + chartHeight - barHeight - 18),
                              withAttributes: [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: barColors[i % barColors.count]])
            }

            // Color legend / pie-like sections below
            var legendY = chartY + chartHeight + 40
            "Distribution by Category".draw(
                at: CGPoint(x: margin, y: legendY),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.black]
            )
            legendY += 30

            let categories: [(String, UIColor, CGFloat)] = [
                ("Mobile", .systemBlue, 0.45),
                ("Desktop", .systemGreen, 0.30),
                ("Tablet", .systemOrange, 0.15),
                ("Other", .systemGray, 0.10),
            ]

            // Horizontal stacked bar
            let stackBarY = legendY
            var stackX: CGFloat = margin
            let stackWidth = pageRect.width - margin * 2
            let stackHeight: CGFloat = 30

            for (_, color, fraction) in categories {
                let w = stackWidth * fraction
                color.setFill()
                UIRectFill(CGRect(x: stackX, y: stackBarY, width: w, height: stackHeight))
                stackX += w
            }
            legendY += stackHeight + 10

            // Legend items
            for (name, color, fraction) in categories {
                color.setFill()
                UIRectFill(CGRect(x: margin, y: legendY + 2, width: 12, height: 12))
                "\(name) — \(Int(fraction * 100))%".draw(
                    at: CGPoint(x: margin + 20, y: legendY),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black]
                )
                legendY += 20
            }

            // Page 3: Another table with colored cell backgrounds
            context.beginPage()
            "Status Dashboard".draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttrs)

            drawColoredStatusTable(at: CGPoint(x: margin, y: margin + 50),
                                   width: pageRect.width - margin * 2,
                                   in: context)
        }

        return PDFDocument(data: data)
    }

    // MARK: - Table Drawing Helpers

    private static func drawTable(at origin: CGPoint, width: CGFloat,
                                   headers: [String], rows: [[String]],
                                   in context: UIGraphicsPDFRendererContext) {
        let colCount = headers.count
        let colWidth = width / CGFloat(colCount)
        let rowHeight: CGFloat = 28
        let headerFont = UIFont.boldSystemFont(ofSize: 12)
        let cellFont = UIFont.systemFont(ofSize: 12)

        // Header background
        UIColor(red: 0.15, green: 0.35, blue: 0.6, alpha: 1).setFill()
        UIRectFill(CGRect(x: origin.x, y: origin.y, width: width, height: rowHeight))

        // Header text
        for (i, header) in headers.enumerated() {
            header.draw(
                in: CGRect(x: origin.x + CGFloat(i) * colWidth + 8, y: origin.y + 6, width: colWidth - 16, height: rowHeight),
                withAttributes: [.font: headerFont, .foregroundColor: UIColor.white]
            )
        }

        // Rows
        for (rowIdx, row) in rows.enumerated() {
            let rowY = origin.y + CGFloat(rowIdx + 1) * rowHeight
            let bgColor = rowIdx % 2 == 0 ? UIColor(white: 0.95, alpha: 1) : UIColor.white
            bgColor.setFill()
            UIRectFill(CGRect(x: origin.x, y: rowY, width: width, height: rowHeight))

            for (colIdx, cell) in row.enumerated() {
                var textColor = UIColor.black
                // Color the "Change" column
                if colIdx == 3 {
                    if cell.hasPrefix("+") { textColor = UIColor(red: 0, green: 0.6, blue: 0, alpha: 1) }
                    else if cell.hasPrefix("-") { textColor = UIColor(red: 0.8, green: 0, blue: 0, alpha: 1) }
                }
                cell.draw(
                    in: CGRect(x: origin.x + CGFloat(colIdx) * colWidth + 8, y: rowY + 6, width: colWidth - 16, height: rowHeight),
                    withAttributes: [.font: cellFont, .foregroundColor: textColor]
                )
            }

            // Row border
            UIColor(white: 0.8, alpha: 1).setStroke()
            let borderPath = UIBezierPath(rect: CGRect(x: origin.x, y: rowY, width: width, height: rowHeight))
            borderPath.lineWidth = 0.5
            borderPath.stroke()
        }

        // Outer border
        UIColor(white: 0.6, alpha: 1).setStroke()
        let outerBorder = UIBezierPath(rect: CGRect(x: origin.x, y: origin.y, width: width, height: CGFloat(rows.count + 1) * rowHeight))
        outerBorder.lineWidth = 1
        outerBorder.stroke()
    }

    private static func drawColoredStatusTable(at origin: CGPoint, width: CGFloat,
                                                in context: UIGraphicsPDFRendererContext) {
        let statuses: [(String, String, UIColor)] = [
            ("API Server", "Running", UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 0.3)),
            ("Database", "Running", UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 0.3)),
            ("Cache", "Warning", UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.3)),
            ("Queue Worker", "Stopped", UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.3)),
            ("CDN", "Running", UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 0.3)),
            ("Auth Service", "Degraded", UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.3)),
            ("Search Index", "Running", UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 0.3)),
            ("Email Service", "Stopped", UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.3)),
        ]

        let rowHeight: CGFloat = 32
        let headerFont = UIFont.boldSystemFont(ofSize: 13)
        let cellFont = UIFont.systemFont(ofSize: 13)
        let statusFont = UIFont.boldSystemFont(ofSize: 13)
        let colWidths: [CGFloat] = [width * 0.5, width * 0.3, width * 0.2]

        // Header
        UIColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1).setFill()
        UIRectFill(CGRect(x: origin.x, y: origin.y, width: width, height: rowHeight))
        let headers = ["Service", "Status", "Uptime"]
        var xOff: CGFloat = origin.x
        for (i, header) in headers.enumerated() {
            header.draw(
                in: CGRect(x: xOff + 8, y: origin.y + 8, width: colWidths[i] - 16, height: rowHeight),
                withAttributes: [.font: headerFont, .foregroundColor: UIColor.white]
            )
            xOff += colWidths[i]
        }

        // Rows
        let uptimes = ["99.99%", "99.95%", "98.5%", "0%", "99.9%", "95.2%", "99.8%", "0%"]
        for (idx, (service, status, bgColor)) in statuses.enumerated() {
            let rowY = origin.y + CGFloat(idx + 1) * rowHeight
            bgColor.setFill()
            UIRectFill(CGRect(x: origin.x, y: rowY, width: width, height: rowHeight))

            var statusColor = UIColor.black
            switch status {
            case "Running": statusColor = UIColor(red: 0, green: 0.6, blue: 0, alpha: 1)
            case "Warning": statusColor = UIColor(red: 0.8, green: 0.6, blue: 0, alpha: 1)
            case "Degraded": statusColor = .orange
            case "Stopped": statusColor = UIColor(red: 0.8, green: 0, blue: 0, alpha: 1)
            default: break
            }

            service.draw(
                in: CGRect(x: origin.x + 8, y: rowY + 8, width: colWidths[0] - 16, height: rowHeight),
                withAttributes: [.font: cellFont, .foregroundColor: UIColor.black]
            )
            status.draw(
                in: CGRect(x: origin.x + colWidths[0] + 8, y: rowY + 8, width: colWidths[1] - 16, height: rowHeight),
                withAttributes: [.font: statusFont, .foregroundColor: statusColor]
            )
            uptimes[idx].draw(
                in: CGRect(x: origin.x + colWidths[0] + colWidths[1] + 8, y: rowY + 8, width: colWidths[2] - 16, height: rowHeight),
                withAttributes: [.font: cellFont, .foregroundColor: UIColor.black]
            )

            // Border
            UIColor(white: 0.7, alpha: 1).setStroke()
            UIBezierPath(rect: CGRect(x: origin.x, y: rowY, width: width, height: rowHeight)).stroke()
        }
    }
}
