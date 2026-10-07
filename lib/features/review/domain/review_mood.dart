/// Mood of the day. All four options are positive; there is no clearing.
const List<String> reviewMoodLabels = ['Good', 'Great', 'Excellent', 'Legendary'];
const int reviewDefaultMood = 1;

String reviewMoodLabel(int mood) => reviewMoodLabels[(mood.clamp(1, 4)) - 1];
