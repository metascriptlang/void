use gpui::{
    App, AnyView, Bounds, ContentMask, Context, Entity, Font, FontFeatures, FontId,
    FrameEvent, FrameTimingCollector, Hsla, Pixels, Render, ShapedLine, StyleRefinement,
    TextAlign, TextRenderingMode, TextRun, Window, WindowBounds, WindowOptions,
    canvas, div, fill, font, point, prelude::*, px, size,
};
use gpui_platform::application;
use std::{borrow::Cow, cell::RefCell, rc::Rc, sync::Arc, time::Instant};

const WIDTH: f32 = 1280.0;
const HEIGHT: f32 = 720.0;
const WARM: usize = 20;
const MEASURED: usize = 120;
const LINE: &str = "let total = compute(alpha, beta) + table[index] * 3; // editor 0123456789";
const INTER_BYTES: &[u8] = include_bytes!("../../../../../assets/font.ttf");
const CASCADIA_BYTES: &[u8] = include_bytes!("../../../../../tests/fonts/cascadiaSubset.ttf");
const EDITOR_PHASES: &[&str] = &["still", "caret", "selection", "editSame", "splice"];
const TERMINAL_PHASES: &[&str] = &["still", "oneRow", "spliceRow", "scroll", "recycle", "rewrite", "perCellRuns"];

fn fail(message: impl std::fmt::Display) -> ! {
    eprintln!("FAIL currentGpuiBench: {message}");
    std::process::exit(1);
}

fn ink() -> Hsla { colour(0.9, 0.9, 0.95, 1.0) }
fn colour(r: f32, g: f32, b: f32, a: f32) -> Hsla {
    gpui::Rgba { r, g, b, a }.into()
}
fn rectangle(x: f32, y: f32, width: f32, height: f32) -> Bounds<Pixels> {
    Bounds::new(point(px(x), px(y)), size(px(width), px(height)))
}
fn face(bytes: &'static [u8]) -> ttf_parser::Face<'static> {
    ttf_parser::Face::parse(bytes, 0).unwrap_or_else(|error| fail(error))
}

fn optional_env(name: &str) -> Option<String> {
    match std::env::var(name) {
        Ok(value) => Some(value),
        Err(std::env::VarError::NotPresent) => None,
        Err(error) => fail(format!("{name}: {error}")),
    }
}

unsafe extern "C" {
    fn clock_gettime(clock: i32, ts: *mut [i64; 2]) -> i32;
}
// CLOCK_PROCESS_CPUTIME_ID on macOS: own-process CPU time (user+system, all threads), ns.
const CLOCK_PROCESS_CPUTIME_ID: i32 = 12;

fn process_cpu_ns() -> u64 {
    let mut ts = [0_i64; 2];
    if unsafe { clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &mut ts) } != 0 {
        fail(format!("clock_gettime: {}", std::io::Error::last_os_error()));
    }
    ts[0] as u64 * 1_000_000_000 + ts[1] as u64
}

struct Row {
    line: ShapedLine,
    top: f32,
}

struct Data {
    kind: String,
    font_bytes: &'static [u8],
    font: Font,
    font_id: FontId,
    ascent: f32,
    line_height: f32,
    rows: Vec<Row>,
    scroll: f32,
    blink_clock: f32,
    blinking: bool,
    selection_length: usize,
    editor_width: f32,
    validate: bool,
}

impl Data {
    fn run(&self, length: usize, colour: Hsla) -> TextRun {
        TextRun {
            len: length, font: self.font.clone(), color: colour,
            background_color: None, underline: None, strikethrough: None,
        }
    }

    fn shape(&self, text: String, runs: Vec<TextRun>, terminal: bool, window: &Window) -> ShapedLine {
        if !self.validate {
            return window.text_system().shape_line(text.into(), px(13.0), &runs, terminal.then(|| px(8.0)));
        }
        if !text.is_ascii() || text.contains('\n') || runs.iter().map(|run| run.len).sum::<usize>() != text.len() {
            fail("unsupported text or incomplete style runs");
        }
        let line = window.text_system().shape_line(text.clone().into(), px(13.0), &runs, terminal.then(|| px(8.0)));
        let natural = terminal.then(|| window.text_system().shape_line(text.clone().into(), px(13.0), &runs, None));
        let face = face(self.font_bytes);
        let mut count = 0;
        for run in &line.runs {
            if run.font_id != self.font_id { fail("font fallback/substitution"); }
            for glyph in &run.glyphs {
                if glyph.index != count { fail("unsupported reordered or clustered ASCII shape"); }
                let Some(byte) = text.as_bytes().get(glyph.index) else { fail("glyph index outside text"); };
                let expected = face.glyph_index(char::from(*byte));
                if expected.map(|id| u32::from(id.0)) != Some(glyph.id.0) || glyph.is_emoji {
                    fail(format!("shaping changed ASCII glyph identity; feature/font match not established: glyph {} byte {:?} got {} expected {:?}", glyph.index, text.as_bytes().get(glyph.index), glyph.id.0, expected));
                }
                if let Some(natural) = &natural {
                    let Some(original) = natural.runs.iter().flat_map(|run| &run.glyphs).find(|original| original.index == glyph.index) else { fail("missing unforced glyph"); };
                    let natural_x = f32::from(original.position.x);
                    let cell_x = glyph.index as f32 * 8.0;
                    let expected_x = if (natural_x - cell_x).abs() > 1.0 { cell_x } else { natural_x };
                    if (f32::from(glyph.position.x) - expected_x).abs() > 0.01 {
                        fail(format!("GPUI force_width differs from Void ASCII cluster policy at byte{}: actual={} expected={expected_x}", glyph.index, f32::from(glyph.position.x)));
                    }
                }
                count += 1;
            }
        }
        if count != text.len() { fail("ASCII glyph count mismatch"); }
        line
    }

    fn terminal_row(&self, seed: usize, length: usize, dense: bool, window: &Window) -> ShapedLine {
        let text: String = (0..length).map(|index| char::from((33 + (seed * 7 + index * 13) % 90) as u8)).collect();
        let green = colour(0.5, 0.8, 0.4, 1.0);
        let runs = if dense {
            (0..length).map(|index| self.run(1, if index % 2 == 0 { green } else { ink() })).collect()
        } else {
            let first = length / 3;
            vec![self.run(first, green), self.run(first, ink()), self.run(length - 2 * first, colour(0.8, 0.5, 0.9, 1.0))]
        };
        self.shape(text, runs, true, window)
    }

    fn mutate(&mut self, phase: &str, within: usize, step: usize, window: &Window) -> bool {
        match phase {
            "still" => false,
            "caret" => {
                if within == 0 { self.blinking = true; self.blink_clock = 0.0; }
                self.blink_clock += 0.01_f32;
                true
            }
            "selection" => { self.selection_length = 200 + step % 20; true }
            "editSame" | "splice" => {
                for index in 0..200 {
                    let text = if index == 10 && step % 2 == 1 {
                        if phase == "splice" { format!("x{LINE}") }
                        else { format!("var {}", LINE.get(4..).unwrap_or_else(|| fail("editor prefix"))) }
                    } else { LINE.to_owned() };
                    let runs = vec![self.run(4, colour(0.8, 0.5, 0.9, 1.0)), self.run(text.len() - 4, ink())];
                    self.rows[index].line = self.shape(text, runs, false, window);
                }
                self.editor_width = self.rows.iter().map(|row| f32::from(row.line.width)).fold(0.0, f32::max);
                true
            }
            "oneRow" | "spliceRow" => {
                let length = if phase == "spliceRow" && step % 2 == 1 { 151 } else { 150 };
                let line = self.terminal_row(step + 1000, length, false, window);
                self.rows[step % 60].line = line;
                true
            }
            "scroll" => { self.scroll = ((step * 37) % 200) as f32; true }
            "recycle" => {
                self.rows.remove(0);
                let line = self.terminal_row(step + 1000, 150, false, window);
                self.rows.push(Row { line, top: 59.0 * 15.0 });
                for (index, row) in self.rows.iter_mut().enumerate() { row.top = index as f32 * 15.0; }
                true
            }
            "rewrite" | "perCellRuns" => {
                for index in 0..60 {
                    self.rows[index].line = self.terminal_row(step + index + 2000, 150, phase == "perCellRuns", window);
                }
                true
            }
            _ => fail("unsupported phase"),
        }
    }

    fn paint_selection(&self, window: &mut Window) {
        if self.selection_length == 0 { return; }
        let start = 10;
        let end = start + self.selection_length;
        let mut offset = 0;
        let mut spans = Vec::new();
        for row in &self.rows {
            let length = row.line.text.len();
            if end > offset && start < offset + length + 1 {
                let left = start.saturating_sub(offset).min(length);
                let right = end.saturating_sub(offset).min(length);
                let x0 = 8.0 + f32::from(row.line.x_for_index(left));
                let x1 = 8.0 + if end > offset + length { self.editor_width }
                    else { f32::from(row.line.x_for_index(right)) };
                if x1 > x0 { spans.push((x0, x1, 8.0 + row.top)); }
            }
            offset += length + 1;
        }
        let (Some(first), Some(last)) = (spans.first(), spans.last()) else { return; };
        let radius = px(2.0);
        let vertical = point(px(0.0), radius);
        let horizontal = |left: f32, right: f32| point(px(((right - left) * 0.5).min(2.0)), px(0.0));
        let top_left = point(px(first.0), px(first.2));
        let top_right = point(px(first.1), px(first.2));
        let top_curve = horizontal(first.0, first.1);
        let mut builder = gpui::PathBuilder::fill();
        builder.move_to(top_right - top_curve);
        builder.curve_to(top_right + vertical, top_right);
        for (index, span) in spans.iter().enumerate() {
            let bottom_right = point(px(span.1), px(span.2 + self.line_height));
            if let Some(next) = spans.get(index + 1) {
                let next_right = point(px(next.1), bottom_right.y);
                if next.1 == span.1 { builder.line_to(bottom_right); }
                else {
                    let curve = horizontal(next.1.min(span.1), next.1.max(span.1));
                    builder.line_to(bottom_right - vertical);
                    if next.1 < span.1 {
                        builder.curve_to(bottom_right - curve, bottom_right);
                        builder.line_to(next_right + curve);
                    } else {
                        builder.curve_to(bottom_right + curve, bottom_right);
                        builder.line_to(next_right - curve);
                    }
                    builder.curve_to(next_right + vertical, next_right);
                }
            } else {
                let curve = horizontal(span.0, span.1);
                builder.line_to(bottom_right - vertical);
                builder.curve_to(bottom_right - curve, bottom_right);
                let bottom_left = point(px(span.0), bottom_right.y);
                builder.line_to(bottom_left + curve);
                builder.curve_to(bottom_left - vertical, bottom_left);
            }
        }
        if first.0 > last.0 {
            let curve = horizontal(last.0, first.0);
            let second_left = point(px(last.0), px(first.2 + self.line_height));
            builder.line_to(second_left + vertical);
            builder.curve_to(second_left + curve, second_left);
            let first_bottom = point(px(first.0), second_left.y);
            builder.line_to(first_bottom - curve);
            builder.curve_to(first_bottom - vertical, first_bottom);
        }
        builder.line_to(top_left + vertical);
        builder.curve_to(top_left + top_curve, top_left);
        builder.line_to(top_right - top_curve);
        let path = builder.build().unwrap_or_else(|error| fail(error));
        window.paint_path(path, colour(0.3, 0.5, 0.9, 0.5));
    }

    fn paint(&self, window: &mut Window, cx: &mut App) {
        let paint = |window: &mut Window, cx: &mut App| {
            if self.kind == "editor" { self.paint_selection(window); }
            for row in &self.rows {
                let top = 8.0 + row.top - self.scroll;
                let height = row.line.ascent + row.line.descent;
                let origin = point(px(8.0), px(top + self.ascent) - row.line.ascent);
                if let Err(error) = row.line.paint(origin, height, TextAlign::Left, None, window, cx) { fail(error); }
            }
            if self.kind == "editor" && (!self.blinking || (self.blink_clock / 0.01_f32).floor() as usize % 2 == 0) {
                let Some(row) = self.rows.first() else { fail("missing editor row"); };
                let x = f32::from(row.line.x_for_index(10));
                window.paint_quad(fill(rectangle((8.0 + x).round(), 8.0, 2.0, self.line_height.round()), ink()));
            }
        };
        if self.kind == "terminal" {
            window.with_content_mask(Some(ContentMask { bounds: rectangle(8.0, 8.0, 1264.0, 704.0) }), |window| paint(window, cx));
        } else {
            paint(window, cx);
        }
    }
}

struct Scene { data: Rc<RefCell<Data>> }
impl Render for Scene {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let data = self.data.clone();
        canvas(|_, _, _| (), move |_, _, window, cx| data.borrow().paint(window, cx)).size_full()
    }
}

struct Tag {
    phase: &'static str, within: usize, step: usize,
    mutation_ns: u128, started: Instant, cpu_ns: u64,
}
struct Controller {
    scene: Entity<Scene>,
    data: Rc<RefCell<Data>>,
    collector: FrameTimingCollector,
    frame: usize,
    pending: Option<Tag>,
    capture_phase: Option<String>,
    phase_list: Vec<&'static str>,
}

impl Controller {
    fn phases(&self) -> &[&'static str] { &self.phase_list }

    fn collect(&mut self, window: &Window) {
        let events = self.collector.collect_unseen();
        let Some(tag) = self.pending.take() else { return; };
        let mut draw = None;
        let mut present = None;
        for event in events {
            match event {
                FrameEvent::Draw(timing) if timing.window_id == window.window_handle().window_id() => {
                    if draw.replace(timing).is_some() { fail("multiple Draw events per tagged mutation"); }
                }
                FrameEvent::Present(timing) if timing.window_id == window.window_handle().window_id() => {
                    if present.replace(timing).is_some() { fail("multiple Present events per tagged mutation"); }
                }
                _ => fail("foreign profiler event"),
            }
        }
        // macOS: the profiler drops a frame drawn before the window's first visibility event, so warm-up frames may lack Present
        if tag.within < WARM && (draw.is_none() || present.is_none()) { return; }
        let (Some(draw), Some(present)) = (draw, present) else { fail(format!("missing Draw/Present for tagged frame: draw={} present={} step={} within={}", draw.is_some(), present.is_some(), tag.step, tag.within)); };
        if draw.draw_start < tag.started || present.present_start < draw.draw_end { fail("profiler event ordering"); }
        if tag.within >= WARM {
            println!("SAMPLE {} {} {} {} {} {} {} {} {} {}",
                self.data.borrow().kind, tag.phase, tag.within - WARM, tag.step, tag.mutation_ns,
                draw.draw_duration().as_nanos(), present.present_duration().as_nanos(),
                draw.dirty_to_draw_duration().map(|duration| duration.as_nanos()).unwrap_or(0),
                present.animation_interval.map(|duration| duration.as_nanos()).unwrap_or(0),
                present.present_end.duration_since(tag.started).as_nanos());
            let cpu = process_cpu_ns().checked_sub(tag.cpu_ns)
                .unwrap_or_else(|| fail("process cpu counter moved backwards"));
            println!("CPU_NS_WITH_HARNESS {} {} {} {}",
                self.data.borrow().kind, tag.phase, tag.within - WARM, cpu);
        }
        if tag.within == WARM + MEASURED - 1 {
            println!("PHASE_DONE {} {}", self.data.borrow().kind, tag.phase);
        }
    }

    fn tick(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if window.scale_factor() != 1.0 || window.viewport_size() != size(px(WIDTH), px(HEIGHT)) {
            fail("requires1280x720 client viewport and physical DPI1");
        }
        self.collect(window);
        if self.frame > 0 && self.frame % (WARM + MEASURED) == 0 {
            let completed = self.phases()[self.frame / (WARM + MEASURED) - 1];
            if self.capture_phase.as_deref() == Some(completed) {
                println!("HOLD explicit capture phase={completed}; close owned window to finish");
                return;
            }
        }
        let phase_index = self.frame / (WARM + MEASURED);
        let Some(&phase) = self.phases().get(phase_index) else {
            println!("DONE finite benchmark");
            cx.quit();
            return;
        };
        let within = self.frame % (WARM + MEASURED);
        let cpu_ns = process_cpu_ns();
        let started = Instant::now();
        let changed = self.data.borrow_mut().mutate(phase, within, self.frame, window);
        if changed { self.scene.update(cx, |_, cx| cx.notify()); }
        self.pending = Some(Tag {
            phase, within, step: self.frame,
            mutation_ns: started.elapsed().as_nanos(), started, cpu_ns,
        });
        self.frame += 1;
        cx.notify();
        let entity = cx.entity();
        window.on_next_frame(move |window, cx| entity.update(cx, |this, cx| this.tick(window, cx)));
    }
}

impl Render for Controller {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let style = StyleRefinement {
            size: gpui::SizeRefinement { width: Some(px(WIDTH).into()), height: Some(px(HEIGHT).into()) },
            ..Default::default()
        };
        div().size_full().bg(colour(0.04, 0.05, 0.07, 1.0)).child(AnyView::from(self.scene.clone()).cached(style))
    }
}

fn main() {
    let kind = std::env::var("GPUI_BENCH_CASE").unwrap_or_else(|_| fail("set GPUI_BENCH_CASE=editor|terminal"));
    if kind != "editor" && kind != "terminal" { fail("unsupported workload"); }
    let font_name = optional_env("GPUI_BENCH_FONT").unwrap_or_else(|| {
        if kind == "terminal" { "cascadia".into() } else { "inter".into() }
    });
    let font_bytes = match font_name.as_str() {
        "inter" => INTER_BYTES,
        "cascadia" => CASCADIA_BYTES,
        _ => fail(format!("unsupported font {font_name}")),
    };
    let capture_phase = optional_env("GPUI_BENCH_CAPTURE_PHASE");
    let all_phases = if kind == "editor" { EDITOR_PHASES } else { TERMINAL_PHASES };
    // GPUI_BENCH_PHASES=a,b keeps those phases in the original order (smoke runs)
    let phase_list: Vec<&'static str> = match optional_env("GPUI_BENCH_PHASES") {
        Some(only) => all_phases.iter().copied().filter(|name| only.split(',').any(|wanted| wanted == *name)).collect(),
        None => all_phases.to_vec(),
    };
    let phases = all_phases;
    if capture_phase.as_ref().is_some_and(|phase| !phases.contains(&phase.as_str())) { fail("unsupported capture phase"); }
    application().run(move |cx: &mut App| {
        cx.set_text_rendering_mode(TextRenderingMode::Grayscale);
        if let Err(error) = cx.text_system().add_fonts(vec![Cow::Borrowed(font_bytes)]) { fail(error); }
        let face = face(font_bytes);
        let family = face.names().into_iter().find_map(|name| {
            if name.name_id == ttf_parser::name_id::FAMILY { name.to_string() } else { None }
        }).unwrap_or_else(|| fail("font has no family name"));
        let expected_family = if font_name == "inter" { "Inter" } else { "Void Code Ligatures" };
        if family != expected_family { fail(format!("unexpected {font_name} family {family}")); }
        let mut font = font(family);
        font.features = FontFeatures(Arc::new(vec![
            ("kern".into(), 1), ("liga".into(), 0), ("clig".into(), 0),
            ("dlig".into(), 0), ("hlig".into(), 0), ("calt".into(), 0),
        ]));
        let font_id = cx.text_system().resolve_font(&font);
        if cx.text_system().units_per_em(font_id) != u32::from(face.units_per_em()) { fail("resolved font units mismatch"); }
        let scale = 13.0 / f32::from(face.units_per_em());
        let hhea = face.tables().hhea;
        let ascent = f32::from(hhea.ascender) * scale;
        let line_height = f32::from(hhea.ascender - hhea.descender + hhea.line_gap) * scale;
        println!("INFO source=b961b4950febbc050081554bafe976b5d1b93f39 case={kind} font={font_name} viewport=1280x720 dpi=1 size=13 forceWidth={} hheaAscent={ascent} lineHeight={line_height} aa=grayscale gamma=platform-default", if kind == "terminal" { 8 } else { 0 });
        println!("CONTRACT mutation_ns=model+shape+notify; draw_ns=Window::draw; present_ns=platform render+present (Metal); interval_ns=present interval; callback_to_present_ns=foreground span through platform present, NOT GPU elapsed or Void's pre-host-present span");
        println!("CPU_NS_WITH_HARNESS: own process CPU time (user+system, all threads, CLOCK_PROCESS_CPUTIME_ID, ns NOT cycles) through next callback/sample logging; includes other own threads; not GPU time or WindowServer CPU");
        println!("SCOPE editor=all5 and terminal=all7 original phases; warm=20 measured=120; selection_path=GPUI editor HighlightedRange::paint_lines at b961; Void uses Makepad connected SDF, so corner pixels are not asserted identical; rasterizer/pixels NOT verified");
        println!("COLUMNS SAMPLE case phase sample step mutation_ns draw_ns present_ns dirty_to_draw_ns interval_ns callback_to_present_ns");
        let mut data = Data { kind, font_bytes, font, font_id, ascent, line_height, rows: Vec::new(), scroll: 0.0, blink_clock: 0.0, blinking: false, selection_length: 0, editor_width: 0.0, validate: true };
        gpui::set_trace_enabled(true);
        let bounds = Bounds::new(point(px(100.0), px(100.0)), size(px(WIDTH), px(HEIGHT)));
        let opened = cx.open_window(WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)), titlebar: None, ..Default::default()
        }, move |window, cx| {
            window.set_window_title("Current GPUI editor/terminal comparison");
            println!("PLATFORM scale={} viewport={:?} gpu={:?}", window.scale_factor(), window.viewport_size(), window.gpu_specs());
            if data.kind == "editor" {
                for index in 0..200 {
                    let runs = vec![data.run(4, colour(0.8, 0.5, 0.9, 1.0)), data.run(LINE.len() - 4, ink())];
                    let line = data.shape(LINE.into(), runs, false, window);
                    data.rows.push(Row { line, top: index as f32 * line_height });
                }
            } else {
                for index in 0..60 {
                    let line = data.terminal_row(index, 150, false, window);
                    data.rows.push(Row { line, top: index as f32 * 15.0 });
                }
            }
            data.editor_width = data.rows.iter().map(|row| f32::from(row.line.width)).fold(0.0, f32::max);
            data.validate = match optional_env("GPUI_BENCH_VALIDATE").as_deref() {
                None | Some("0") => false,
                Some("1") => true,
                Some(value) => fail(format!("unsupported GPUI_BENCH_VALIDATE={value}")),
            };
            println!("MODE validateEveryMutation={} initialGlyphIdentityChecks=always", data.validate);
            let data = Rc::new(RefCell::new(data));
            let scene = cx.new(|_| Scene { data: data.clone() });
            let root = cx.new(|_| Controller { scene, data, collector: FrameTimingCollector::new(), frame: 0, pending: None, capture_phase, phase_list });
            let entity = root.clone();
            window.on_next_frame(move |window, cx| entity.update(cx, |this, cx| this.tick(window, cx)));
            root
        });
        if let Err(error) = opened { fail(error); }
        cx.activate(true);
    });
}
