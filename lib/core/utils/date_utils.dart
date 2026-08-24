DateTime startOfDay(DateTime dateTime) =>
    DateTime(dateTime.year, dateTime.month, dateTime.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime addDays(DateTime dateTime, int days) =>
    startOfDay(dateTime).add(Duration(days: days));

int minutesSinceMidnight(DateTime dateTime) =>
    dateTime.hour * 60 + dateTime.minute;
