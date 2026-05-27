#!/usr/bin/env ruby

require "fileutils"
require "yaml"

INPUT = ARGV[0] || "content/crohn-ipi-diffusion.yaml"
METADATA_OUT = ARGV[1] || "content/generated-poster-metadata.tex"
BODY_OUT = ARGV[2] || "content/generated-poster-body.tex"

data = YAML.load_file(INPUT)
poster = data.fetch("poster")
sections = data.fetch("sections").each_with_object({}) do |section, index|
  index[section.fetch("id")] = section
end

def latex_escape(value)
  value.to_s
       .gsub("’", "'")
       .gsub("–", "-")
       .gsub("—", "---")
       .gsub("\\", "\\textbackslash{}")
       .gsub("&", "\\&")
       .gsub("%", "\\%")
       .gsub("$", "\\$")
       .gsub("#", "\\#")
       .gsub("_", "\\_")
       .gsub("{", "\\{")
       .gsub("}", "\\}")
       .gsub("~", "\\textasciitilde{}")
       .gsub("^", "\\textasciicircum{}")
       .gsub("<", "\\textless{}")
       .gsub(">", "\\textgreater{}")
end

def latex_path(path)
  path.to_s
end

def logo_paths(value)
  case value
  when Array
    value.map(&:to_s)
  when nil
    []
  else
    value.to_s.empty? ? [] : [value.to_s]
  end
end

def render_logo_group(paths, height_cm)
  paths.select { |path| File.exist?(path) }
       .map { |path| "\\includegraphics[height=#{height_cm}cm]{#{latex_path(path)}}" }
       .join("\\hspace{1.1cm}")
end

def paragraphs(text)
  text.to_s
      .split(/\n{2,}/)
      .map { |paragraph| latex_escape(paragraph.strip.gsub(/\s*\n\s*/, " ")) }
      .reject(&:empty?)
end

def render_body_text(text)
  paragraphs(text).join("\n\n")
end

def render_itemize(items)
  return "" if items.nil? || items.empty?

  lines = ["\\begin{itemize}"]
  items.each do |item|
    lines << "  \\item #{latex_escape(item)}"
  end
  lines << "\\end{itemize}"
  lines.join("\n")
end

def table_cell(value, bold = false)
  formatted = value.is_a?(Numeric) ? format("%.4f", value) : latex_escape(value)
  bold ? "\\textbf{#{formatted}}" : formatted
end

def bold_table_cell?(table, row, column, row_index, column_index)
  Array(table["bold_cells"]).any? do |cell|
    row_matches =
      if cell.key?("row")
        row.first.to_s == cell["row"].to_s
      elsif cell.key?("row_index")
        row_index == cell["row_index"].to_i
      else
        false
      end

    column_matches =
      if cell.key?("column")
        column.to_s == cell["column"].to_s
      elsif cell.key?("column_index")
        column_index == cell["column_index"].to_i
      else
        false
      end

    row_matches && column_matches
  end
end

def render_table(table)
  return "" unless table

  columns = table.fetch("columns")
  rows = table.fetch("rows")
  spec =
    if columns.length == 2
      "@{}>{\\raggedright\\arraybackslash}p{0.34\\linewidth}>{\\raggedright\\arraybackslash}p{0.56\\linewidth}@{}"
    elsif columns.length == 4
      "@{}>{\\raggedright\\arraybackslash}Xrrr@{}"
    else
      "@{}#{Array.new(columns.length, "l").join}@{}"
    end

  environment = columns.length == 4 ? "tabularx" : "tabular"
  begin_line =
    if environment == "tabularx"
      "\\begin{tabularx}{\\linewidth}{#{spec}}"
    else
      "\\begin{tabular}{#{spec}}"
    end

  lines = [
    "\\begin{center}",
    "{\\scriptsize",
    "\\renewcommand{\\arraystretch}{1.12}",
    begin_line,
    "\\toprule",
    columns.map { |column| "\\textbf{#{latex_escape(column)}}" }.join(" & ") + " \\\\",
    "\\midrule"
  ]
  rows.each_with_index do |row, row_index|
    cells = row.each_with_index.map do |cell, column_index|
      table_cell(cell, bold_table_cell?(table, row, columns[column_index], row_index, column_index))
    end
    lines << cells.join(" & ") + " \\\\"
  end
  lines += [
    "\\bottomrule",
    "\\end{#{environment}}",
    "}",
    "\\par\\smallskip",
    "{\\footnotesize\\itshape #{latex_escape(table["caption"])}\\par}",
    "\\end{center}"
  ]
  lines.join("\n")
end

def figure_items(figures)
  case figures
  when Hash
    figures.fetch("items", [])
  else
    figures
  end
end

def figure_layout(figures)
  figures.is_a?(Hash) ? figures["layout"] : nil
end

def figure_default_height(figures)
  figures.is_a?(Hash) ? figures["height_cm"] : nil
end

def figure_shared_caption(figures)
  figures.is_a?(Hash) ? figures["caption"] : nil
end

def render_figure_image(figure, default_height_cm = nil, width_scale = nil)
  path = figure["path"].to_s
  width = width_scale || figure.fetch("width", 0.98)
  height = figure.fetch("height_cm", default_height_cm || 8.0)

  if !path.empty? && File.exist?(path)
    "\\includegraphics[width=#{width}\\linewidth,height=#{height}cm,keepaspectratio]{#{latex_path(path)}}"
  else
    [
      "\\fbox{%",
      "\\begin{minipage}[c][3.4cm][c]{0.9\\linewidth}",
      "\\centering\\footnotesize Figure placeholder\\\\",
      "\\scriptsize #{latex_escape(figure.fetch("id"))}",
      "\\end{minipage}%",
      "}"
    ].join("\n")
  end
end

def render_single_figure(figure, default_height_cm = nil)
  top_padding = figure["top_padding_cm"]
  lines = ["\\begin{center}"]
  lines << "\\vspace*{#{top_padding}cm}" if top_padding
  lines += [
    render_figure_image(figure, default_height_cm),
    "\\par\\vspace{0.35ex}",
    "{\\scriptsize\\itshape #{latex_escape(figure["caption"])}\\par}",
    "\\end{center}"
  ]
  lines.join("\n")
end

def render_side_by_side_figures(figures, default_height_cm = nil)
  items = figure_items(figures)
  return "" if items.empty?

  item_width = figures.is_a?(Hash) ? figures.fetch("item_width", 0.485) : 0.485
  gap_width = figures.is_a?(Hash) ? figures.fetch("gap_width", 0.03) : 0.03
  cells = items.map do |figure|
    [
      "\\begin{minipage}[t]{#{item_width}\\linewidth}",
      "\\centering",
      render_figure_image(figure, default_height_cm, 1.0),
      "\\par\\vspace{0.25ex}",
      "{\\scriptsize\\itshape #{latex_escape(figure["caption"])}\\par}",
      "\\end{minipage}"
    ].join("\n")
  end

  [
    "{\\hfuzz=30pt",
    "\\begin{center}",
    "\\makebox[\\linewidth][c]{%",
    cells.join("\\hspace{#{gap_width}\\linewidth}\n"),
    "}%",
    "\\end{center}",
    "}"
  ].join("\n")
end

def render_class_grid(figures)
  items = figure_items(figures)
  return "" if items.empty?

  columns = figures.fetch("columns", 4)
  item_width = figures.fetch("item_width", 0.235)
  gap_width = figures.fetch("gap_width", 0.015)
  image_height = figures.fetch("image_height_cm", 7.0)
  rows = items.each_slice(columns).to_a

  lines = [
    "\\begin{center}",
    "{\\setlength{\\tabcolsep}{0pt}%"
  ]

  rows.each_with_index do |row, row_index|
    lines << "\\makebox[\\linewidth][c]{%"
    row.each_with_index do |figure, index|
      path = figure["path"].to_s
      image =
        if !path.empty? && File.exist?(path)
          "\\includegraphics[width=\\linewidth,height=#{image_height}cm,keepaspectratio]{#{latex_path(path)}}"
        else
          [
            "\\fbox{%",
            "\\begin{minipage}[c][#{image_height}cm][c]{\\linewidth}",
            "\\centering\\footnotesize Missing image",
            "\\end{minipage}%",
            "}"
          ].join("\n")
        end

      lines << "\\begin{minipage}[t]{#{item_width}\\linewidth}"
      lines << "\\centering"
      lines << image
      lines << "\\par\\vspace{0.2ex}{\\scriptsize\\textbf{#{latex_escape(figure.fetch("label"))}}\\par}"
      lines << "\\end{minipage}"
      lines << "\\hspace{#{gap_width}\\linewidth}" unless index == row.length - 1
    end
    lines << "}%"
    lines << "\\par\\vspace{0.55ex}" unless row_index == rows.length - 1
  end

  if figure_shared_caption(figures)
    lines << "\\par\\vspace{0.35ex}"
    lines << "{\\scriptsize\\itshape #{latex_escape(figure_shared_caption(figures))}\\par}"
  end

  lines += [
    "}",
    "\\end{center}"
  ]
  lines.join("\n")
end

def render_figures(figures)
  items = figure_items(figures)
  return "" if items.nil? || items.empty?

  default_height = figure_default_height(figures)
  if figure_layout(figures) == "side_by_side"
    return render_side_by_side_figures(figures, default_height)
  end
  if figure_layout(figures) == "class_grid"
    return render_class_grid(figures)
  end

  items.map do |figure|
    path = figure["path"].to_s
    render_single_figure(figure, default_height)
  end.join("\n")
end

def render_class_table(classes)
  return "" if classes.nil? || classes.empty?

  rows = classes.map do |klass|
    if klass.is_a?(Hash)
      [klass.fetch("code"), klass.fetch("name")]
    else
      [klass, ""]
    end
  end

  lines = [
    "\\begin{center}",
    "{\\footnotesize",
    "\\renewcommand{\\arraystretch}{1.08}",
    "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.24\\linewidth}>{\\raggedright\\arraybackslash}p{0.66\\linewidth}@{}}",
    "\\toprule",
    "\\textbf{Class} & \\textbf{Full name} \\\\",
    "\\midrule"
  ]
  rows.each do |code, name|
    lines << "#{latex_escape(code)} & #{latex_escape(name)} \\\\"
  end
  lines += [
    "\\bottomrule",
    "\\end{tabular}",
    "}",
    "\\end{center}"
  ]
  lines.join("\n")
end

def render_dataset(section)
  lines = []
  lines << "\\textbf{Dataset:} #{latex_escape(section["dataset_name"])}"
  lines << ""
  lines << "\\textbf{Classes:}"
  lines << render_class_table(section.fetch("classes"))
  lines << ""
  lines << "\\textbf{Evaluation setup:} #{latex_escape(section["evaluation_setup"])}"
  lines << ""
  lines << "\\textbf{Main challenge:} #{latex_escape(section["main_challenge"])}"
  lines.join("\n")
end

def render_technical_details(details)
  return "" unless details && details["items"]

  [
    "{\\footnotesize",
    "\\textbf{Filtering thresholds:}",
    render_itemize(details.fetch("items")),
    "}"
  ].join("\n")
end

def render_references(entries)
  return "" if entries.nil? || entries.empty?

  lines = ["\\vspace{0.35ex}{\\scriptsize\\textbf{References}\\par}", "{\\tiny"]
  entries.each_with_index do |entry, index|
    lines << "\\textbf{[#{index + 1}]} #{latex_escape(entry)}\\par"
  end
  lines << "}"
  lines.join("\n")
end

def render_section(section)
  content = []
  content << render_body_text(section["body"]) if section["body"]

  if section["key_question"]
    content << "\\textbf{Key question:} #{latex_escape(section["key_question"])}"
  end

  content << render_dataset(section) if section["dataset_name"]
  content << render_table(section["table"]) if section["table"]
  content << render_technical_details(section["technical_details"]) if section["technical_details"]
  content << "\\textbf{Key result:} #{latex_escape(section["key_result"])}" if section["key_result"]
  content << render_itemize(section["bullets"]) if section["bullets"]
  content << render_references(section["references"]) if section["references"]
  content << render_figures(section["figures"]) if section["figures"]

  [
    "\\begin{block}{#{latex_escape(section.fetch("title"))}}",
    content.reject(&:empty?).join("\n\n"),
    "\\end{block}"
  ].join("\n\n")
end

def render_metadata(poster)
  affiliations = poster.fetch("affiliations")
  affiliation_numbers = affiliations.each_with_index.to_h { |affiliation, index| [affiliation.fetch("id"), index + 1] }

  authors = poster.fetch("authors").map do |author|
    "#{latex_escape(author.fetch("name"))} \\inst{#{affiliation_numbers.fetch(author.fetch("affiliation_id"))}}"
  end.join(" \\and ")

  institutes = affiliations.each_with_index.map do |affiliation, index|
    "\\inst{#{index + 1}} #{latex_escape(affiliation.fetch("name"))}, #{latex_escape(affiliation.fetch("location"))}"
  end.join(" \\samelineand ")

  footer = poster.fetch("footer")
  footer_parts = [footer["left"], footer["center"], footer["right"]].map { |part| latex_escape(part) }

  lines = [
    "% This file is generated from #{INPUT}.",
    "\\title{#{latex_escape(poster.fetch("title"))}}",
    "\\author{#{authors}}",
    "\\institute[University of Calgary]{#{institutes}}",
    "\\footercontent{#{footer_parts.join(" \\hfill ")}}"
  ]

  logos = poster["logos"] || {}
  logo_height = logos.fetch("height_cm", 5.5)
  left_logo_height = logos.fetch("left_height_cm", logo_height)
  right_logo_height = logos.fetch("right_height_cm", logo_height)
  left_logos = render_logo_group(logo_paths(logos["left"]), left_logo_height)
  right_logos = render_logo_group(logo_paths(logos["right"]), right_logo_height)
  if left_logos != ""
    lines << "\\logoleft{#{left_logos}}"
  end
  if right_logos != ""
    lines << "\\logoright{#{right_logos}}"
  end

  lines.join("\n") + "\n"
end

def render_body(poster, sections)
  lines = [
    "% This file is generated from #{INPUT}.",
    "\\begin{frame}[t]",
    "\\begin{columns}[t]",
    "\\separatorcolumn"
  ]

  poster.fetch("layout").fetch("columns").each do |column|
    lines << "\\begin{column}{\\colwidth}"
    column.fetch("sections").each do |section_id|
      section = sections.fetch(section_id)
      lines << render_section(section)
    end
    lines << "\\end{column}"
    lines << "\\separatorcolumn"
  end

  lines += [
    "\\end{columns}",
    "\\end{frame}"
  ]
  lines.join("\n\n") + "\n"
end

FileUtils.mkdir_p(File.dirname(METADATA_OUT))
File.write(METADATA_OUT, render_metadata(poster))
File.write(BODY_OUT, render_body(poster, sections))

puts "Generated #{METADATA_OUT}"
puts "Generated #{BODY_OUT}"
