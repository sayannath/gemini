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

def table_cell(value)
  value.is_a?(Numeric) ? format("%.4f", value) : latex_escape(value)
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
  rows.each do |row|
    lines << row.map { |cell| table_cell(cell) }.join(" & ") + " \\\\"
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

def render_figures(figures)
  return "" if figures.nil? || figures.empty?

  figures.map do |figure|
    path = figure["path"].to_s
    image =
      if !path.empty? && File.exist?(path)
        "\\includegraphics[width=0.95\\linewidth]{#{latex_path(path)}}"
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

    [
      "\\begin{center}",
      image,
      "\\par\\smallskip",
      "{\\footnotesize\\itshape #{latex_escape(figure["caption"])}\\par}",
      "\\end{center}"
    ].join("\n")
  end.join("\n\n")
end

def render_dataset(section)
  lines = []
  lines << "\\textbf{Dataset:} #{latex_escape(section["dataset_name"])}"
  lines << ""
  lines << "\\textbf{Classes:} #{section.fetch("classes").map { |klass| latex_escape(klass) }.join(", ")}"
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
