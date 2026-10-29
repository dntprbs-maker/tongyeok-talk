const creditWarningThreshold = 20;
const creditUrgentThreshold = 5;
String creditWarningKey(int available) {
  if (available <= 0) return 'creditEmpty';
  if (available <= creditUrgentThreshold) return 'creditUrgent';
  if (available <= creditWarningThreshold) return 'creditLow';
  return 'creditHelp';
}
