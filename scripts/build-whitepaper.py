#!/usr/bin/env python3
"""Build the public TinyAI Protocol whitepaper PDF from docs/WHITEPAPER.md."""

from __future__ import annotations

import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "WHITEPAPER.md"
OUTPUT = ROOT / "web" / "public" / "whitepaper" / "TinyAI-Protocol-Whitepaper.pdf"

PAGE_W, PAGE_H = A4
MARGIN_X = 20 * mm
TOP = 21 * mm
BOTTOM = 19 * mm
CONTENT_W = PAGE_W - 2 * MARGIN_X

INK = colors.HexColor("#080A0D")
SURFACE = colors.HexColor("#11151A")
YELLOW = colors.HexColor("#F0B90B")
YELLOW_DARK = colors.HexColor("#806000")
PAPER = colors.HexColor("#F3F0E7")
TEXT = colors.HexColor("#15181C")
MUTED = colors.HexColor("#606872")
LINE = colors.HexColor("#C8C5BC")
LIGHT = colors.HexColor("#E6E2D7")


class TinyAIDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str, **kwargs):
        super().__init__(filename, **kwargs)
        cover_frame = Frame(20 * mm, 22 * mm, PAGE_W - 40 * mm, PAGE_H - 42 * mm, id="cover", showBoundary=0)
        body_frame = Frame(MARGIN_X, BOTTOM, CONTENT_W, PAGE_H - TOP - BOTTOM, id="body", showBoundary=0)
        self.addPageTemplates([
            PageTemplate(id="Cover", frames=[cover_frame], onPage=draw_cover, autoNextPageTemplate="Body"),
            PageTemplate(id="Body", frames=[body_frame], onPage=draw_body),
        ])

    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            style_name = flowable.style.name
            if style_name in {"H1", "H2"}:
                level = 0 if style_name == "H1" else 1
                text = flowable.getPlainText()
                key = "h1" if level == 0 else "h2"
                self.canv.bookmarkPage(f"{key}-{self.page}-{abs(hash(text))}")


def draw_cover(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(PAPER)
    canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    canvas.setFillColor(YELLOW)
    canvas.rect(0, PAGE_H - 8 * mm, PAGE_W, 8 * mm, fill=1, stroke=0)
    canvas.setStrokeColor(colors.HexColor("#DDD7CA"))
    canvas.setLineWidth(.45)
    for x in range(0, int(PAGE_W), int(15 * mm)):
        canvas.line(x, 0, x, PAGE_H)
    for y in range(0, int(PAGE_H), int(15 * mm)):
        canvas.line(0, y, PAGE_W, y)
    canvas.setFillColor(colors.HexColor("#E8E1D3"))
    canvas.setFont("ArialBold", 220)
    canvas.drawRightString(PAGE_W - 11 * mm, 25 * mm, "T")
    canvas.setStrokeColor(YELLOW)
    canvas.setLineWidth(1.2)
    canvas.line(20 * mm, 24 * mm, 70 * mm, 24 * mm)
    canvas.restoreState()


def draw_body(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(PAPER)
    canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    canvas.setStrokeColor(YELLOW)
    canvas.setLineWidth(1.2)
    canvas.line(MARGIN_X, PAGE_H - 13 * mm, MARGIN_X + 28 * mm, PAGE_H - 13 * mm)
    canvas.setFillColor(MUTED)
    canvas.setFont("ArialBold", 7.4)
    canvas.drawString(MARGIN_X + 32 * mm, PAGE_H - 14.1 * mm, "TINYAI PROTOCOL / RESEARCH WHITEPAPER")
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(.45)
    canvas.line(MARGIN_X, 13 * mm, PAGE_W - MARGIN_X, 13 * mm)
    canvas.setFont("Arial", 7.2)
    canvas.drawString(MARGIN_X, 8.5 * mm, "SOVEREIGN ON-CHAIN AI STATE MACHINES FOR THE EVM")
    canvas.setFont("ArialBold", 7.5)
    canvas.drawRightString(PAGE_W - MARGIN_X, 8.5 * mm, f"{doc.page:02d}")
    canvas.restoreState()


def register_fonts():
    regular = "/mnt/c/Windows/Fonts/msyh.ttc"
    bold = "/mnt/c/Windows/Fonts/msyhbd.ttc"
    pdfmetrics.registerFont(TTFont("CJK", regular, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("CJKBold", bold, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("Arial", "/mnt/c/Windows/Fonts/arial.ttf"))
    pdfmetrics.registerFont(TTFont("ArialBold", "/mnt/c/Windows/Fonts/arialbd.ttf"))
    pdfmetrics.registerFontFamily("CJK", normal="CJK", bold="CJKBold", italic="CJK", boldItalic="CJKBold")


def make_styles():
    base = getSampleStyleSheet()
    return {
        "CoverKicker": ParagraphStyle("CoverKicker", fontName="ArialBold", fontSize=8.5, leading=12, textColor=YELLOW_DARK, tracking=1.8, spaceAfter=14 * mm),
        "CoverTitle": ParagraphStyle("CoverTitle", fontName="CJKBold", fontSize=36, leading=45, textColor=TEXT, spaceAfter=6 * mm, wordWrap="CJK"),
        "CoverSubtitle": ParagraphStyle("CoverSubtitle", fontName="ArialBold", fontSize=15, leading=21, textColor=YELLOW_DARK, spaceAfter=11 * mm),
        "CoverAbstract": ParagraphStyle("CoverAbstract", fontName="CJK", fontSize=10.5, leading=18, textColor=MUTED, spaceAfter=13 * mm, wordWrap="CJK"),
        "CoverMeta": ParagraphStyle("CoverMeta", fontName="ArialBold", fontSize=8, leading=12, textColor=colors.HexColor("#4F4A43"), tracking=1.1),
        "TOCTitle": ParagraphStyle("TOCTitle", fontName="CJKBold", fontSize=28, leading=35, textColor=TEXT, spaceAfter=7 * mm, wordWrap="CJK"),
        "TOCIntro": ParagraphStyle("TOCIntro", fontName="CJK", fontSize=9.5, leading=16, textColor=MUTED, spaceAfter=8 * mm, wordWrap="CJK"),
        "TOCItem": ParagraphStyle("TOCItem", fontName="CJK", fontSize=9, leading=14, textColor=TEXT, wordWrap="CJK"),
        "H1": ParagraphStyle("H1", parent=base["Heading1"], fontName="CJKBold", fontSize=22, leading=29, textColor=TEXT, spaceBefore=9 * mm, spaceAfter=5 * mm, keepWithNext=True, wordWrap="CJK"),
        "H2": ParagraphStyle("H2", parent=base["Heading2"], fontName="CJKBold", fontSize=14, leading=20, textColor=TEXT, spaceBefore=6 * mm, spaceAfter=3 * mm, keepWithNext=True, wordWrap="CJK"),
        "Body": ParagraphStyle("Body", parent=base["BodyText"], fontName="CJK", fontSize=9.3, leading=16.2, textColor=TEXT, spaceAfter=4 * mm, wordWrap="CJK", allowWidows=0, allowOrphans=0),
        "Bullet": ParagraphStyle("Bullet", fontName="CJK", fontSize=9, leading=15.5, textColor=TEXT, leftIndent=0, wordWrap="CJK"),
        "Quote": ParagraphStyle("Quote", fontName="CJK", fontSize=9.2, leading=16, textColor=TEXT, wordWrap="CJK"),
        "Code": ParagraphStyle("Code", fontName="Courier", fontSize=7.2, leading=11.2, textColor=TEXT, leftIndent=0),
        "TableHead": ParagraphStyle("TableHead", fontName="CJKBold", fontSize=7.4, leading=10, textColor=INK, wordWrap="CJK"),
        "TableCell": ParagraphStyle("TableCell", fontName="CJK", fontSize=7.5, leading=11.5, textColor=TEXT, wordWrap="CJK"),
        "Caption": ParagraphStyle("Caption", fontName="CJK", fontSize=7.5, leading=12, textColor=MUTED, wordWrap="CJK"),
    }


def inline_markup(value: str) -> str:
    escaped = html.escape(value.strip())
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(r"`([^`]+)`", r'<font name="Courier" color="#9A7600">\1</font>', escaped)
    return escaped


def table_widths(column_count: int):
    if column_count == 5:
        ratios = [.07, .18, .15, .35, .25]
    elif column_count == 4:
        ratios = [.15, .27, .36, .22]
    elif column_count == 3:
        ratios = [.22, .39, .39]
    elif column_count == 2:
        ratios = [.31, .69]
    else:
        ratios = [1 / column_count] * column_count
    return [CONTENT_W * ratio for ratio in ratios]


def markdown_table(rows, styles):
    column_count = len(rows[0])
    formatted = []
    for row_index, row in enumerate(rows):
        style = styles["TableHead"] if row_index == 0 else styles["TableCell"]
        formatted.append([Paragraph(inline_markup(cell), style) for cell in row])
    table = Table(formatted, colWidths=table_widths(column_count), repeatRows=1, hAlign="LEFT")
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), YELLOW),
        ("GRID", (0, 0), (-1, -1), .45, LINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]
    for row_index in range(1, len(rows)):
        if row_index % 2 == 0:
            commands.append(("BACKGROUND", (0, row_index), (-1, row_index), colors.HexColor("#EAE6DC")))
    table.setStyle(TableStyle(commands))
    return table


def bullet_list(items, styles, ordered=False):
    rows = []
    for index, item in enumerate(items):
        marker = f"{index + 1}." if ordered else "-"
        rows.append([
            Paragraph(f'<font color="#B18600"><b>{marker}</b></font>', styles["Bullet"]),
            Paragraph(inline_markup(item), styles["Bullet"]),
        ])
    table = Table(rows, colWidths=[7 * mm, CONTENT_W - 7 * mm], hAlign="LEFT", splitByRow=1)
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (0, -1), 2),
        ("RIGHTPADDING", (1, 0), (1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 1.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1.5),
    ]))
    table.spaceAfter = 4 * mm
    return table


def callout(text: str, styles):
    stripe = Table([["", Paragraph(inline_markup(text), styles["Quote"])]], colWidths=[3.2 * mm, CONTENT_W - 3.2 * mm])
    stripe.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, 0), YELLOW),
        ("BACKGROUND", (1, 0), (1, 0), LIGHT),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("RIGHTPADDING", (0, 0), (0, 0), 0),
        ("LEFTPADDING", (1, 0), (1, 0), 12),
        ("RIGHTPADDING", (1, 0), (1, 0), 12),
        ("TOPPADDING", (1, 0), (1, 0), 10),
        ("BOTTOMPADDING", (1, 0), (1, 0), 10),
    ]))
    return stripe


def parse_markdown(markdown: str, styles):
    lines = markdown.splitlines()
    start = next(i for i, line in enumerate(lines) if line == "## 中文执行摘要")
    lines = lines[start:]
    story = []
    paragraph = []
    index = 0

    def flush_paragraph():
        nonlocal paragraph
        if paragraph:
            story.append(Paragraph(inline_markup(" ".join(part.strip() for part in paragraph)), styles["Body"]))
            paragraph = []

    while index < len(lines):
        line = lines[index].rstrip()
        if not line:
            flush_paragraph()
            index += 1
            continue
        if line == "---":
            flush_paragraph()
            story.append(Spacer(1, 3 * mm))
            index += 1
            continue
        if line.startswith("## "):
            flush_paragraph()
            story.append(Paragraph(inline_markup(line[3:]), styles["H1"]))
            index += 1
            continue
        if line.startswith("### "):
            flush_paragraph()
            story.append(Paragraph(inline_markup(line[4:]), styles["H2"]))
            index += 1
            continue
        if line.startswith("> "):
            flush_paragraph()
            quoted = []
            while index < len(lines) and lines[index].startswith("> "):
                quoted.append(lines[index][2:].strip())
                index += 1
            story.extend([callout(" ".join(quoted), styles), Spacer(1, 4 * mm)])
            continue
        if line.startswith("```"):
            flush_paragraph()
            code = []
            index += 1
            while index < len(lines) and not lines[index].startswith("```"):
                code.append(lines[index])
                index += 1
            index += 1
            code_table = Table([[Preformatted("\n".join(code), styles["Code"])]], colWidths=[CONTENT_W])
            code_table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF6CF")),
                ("BOX", (0, 0), (-1, -1), .6, INK),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
            ]))
            story.extend([code_table, Spacer(1, 4 * mm)])
            continue
        if line.startswith("|"):
            flush_paragraph()
            rows = []
            while index < len(lines) and lines[index].startswith("|"):
                raw = [cell.strip() for cell in lines[index].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-{3,}:?", cell) for cell in raw):
                    rows.append(raw)
                index += 1
            story.extend([markdown_table(rows, styles), Spacer(1, 4 * mm)])
            continue
        if line.startswith("- "):
            flush_paragraph()
            items = []
            while index < len(lines) and lines[index].startswith("- "):
                items.append(lines[index][2:].strip())
                index += 1
            story.append(bullet_list(items, styles))
            continue
        if re.match(r"^\d+\. ", line):
            flush_paragraph()
            items = []
            while index < len(lines) and re.match(r"^\d+\. ", lines[index]):
                items.append(re.sub(r"^\d+\. ", "", lines[index]).strip())
                index += 1
            story.append(bullet_list(items, styles, ordered=True))
            continue
        paragraph.append(line)
        index += 1

    flush_paragraph()
    return story


def cover_story(styles):
    meta = Table([
        [Paragraph("EXECUTION", styles["CoverMeta"]), Paragraph("EVM NATIVE", styles["CoverMeta"])],
        [Paragraph("IDENTITY", styles["CoverMeta"]), Paragraph("ERC-721", styles["CoverMeta"])],
        [Paragraph("EVOLUTION", styles["CoverMeta"]), Paragraph("OWNER CONTROLLED", styles["CoverMeta"])],
        [Paragraph("SETTLEMENT", styles["CoverMeta"]), Paragraph("NON-CUSTODIAL", styles["CoverMeta"])],
    ], colWidths=[55 * mm, 75 * mm], rowHeights=[11 * mm] * 4)
    meta.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), .45, INK),
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#F0B90B")),
        ("BACKGROUND", (1, 0), (1, -1), colors.HexColor("#FFFDF8")),
        ("LEFTPADDING", (0, 0), (-1, -1), 9),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    return [
        Spacer(1, 20 * mm),
        Paragraph("TINYAI PROTOCOL / RESEARCH WHITEPAPER", styles["CoverKicker"]),
        Paragraph("TinyAI Protocol", styles["CoverTitle"]),
        Paragraph("Sovereign On-chain AI State Machines for the EVM", styles["CoverSubtitle"]),
        Paragraph("把小型确定性模型变成可拥有、可验证、可进化的链上状态机。身份、记忆、大脑、组件与交易结算共享同一个公开执行环境。", styles["CoverAbstract"]),
        Spacer(1, 6 * mm),
        meta,
        Spacer(1, 13 * mm),
        Paragraph("AUGUST 2026 / TECHNICAL SPECIFICATION", styles["CoverMeta"]),
        PageBreak(),
    ]


def contents_story(markdown: str, styles):
    headings = [line[3:] for line in markdown.splitlines() if line.startswith("## ") and line not in {"## Sovereign On-chain AI State Machines for the EVM"}]
    rows = []
    for heading in headings:
        section_number = re.match(r"^(\d+)\.", heading)
        if heading == "中文执行摘要":
            label = "中文"
        elif heading == "Abstract":
            label = "ABSTRACT"
        elif section_number:
            label = section_number.group(1).zfill(2)
        elif heading.startswith("Appendix A"):
            label = "A"
        elif heading.startswith("Appendix B"):
            label = "B"
        else:
            label = "NOTE"
        rows.append([
            Paragraph(label, styles["TableHead"]),
            Paragraph(inline_markup(heading), styles["TOCItem"]),
        ])
    table = Table(rows, colWidths=[22 * mm, CONTENT_W - 22 * mm], hAlign="LEFT")
    commands = [
        ("LINEBELOW", (0, 0), (-1, -1), .45, LINE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("TEXTCOLOR", (0, 0), (0, -1), colors.HexColor("#8B6B00")),
    ]
    table.setStyle(TableStyle(commands))
    return [
        Paragraph("Contents", styles["TOCTitle"]),
        Paragraph("本白皮书只描述当前参考实现的协议机制、控制边界和独立验证方法，不以产品历史或营销叙事代替技术事实。", styles["TOCIntro"]),
        table,
        PageBreak(),
    ]


def build():
    register_fonts()
    styles = make_styles()
    markdown = SOURCE.read_text(encoding="utf-8")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = TinyAIDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        leftMargin=MARGIN_X,
        rightMargin=MARGIN_X,
        topMargin=TOP,
        bottomMargin=BOTTOM,
        title="TinyAI Protocol: Sovereign On-chain AI State Machines for the EVM",
        author="TinyAI Protocol",
        subject="Technical whitepaper for the TinyAI Protocol reference implementation",
        creator="TinyAI Protocol",
    )
    story = cover_story(styles) + contents_story(markdown, styles) + parse_markdown(markdown, styles)
    doc.build(story)
    print(OUTPUT)


if __name__ == "__main__":
    build()
