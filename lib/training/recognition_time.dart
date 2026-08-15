/// Recognition time presets in milliseconds, from the spec's recommended
/// list (morse_icr_spec.md section 6). The architecture allows additional
/// values or a custom entry later; this is just the initial preset list.
const List<int> recognitionTimePresetsMs = [
  1000, 750, 500, 250, 200, 150, 100, 75, 50,
];
