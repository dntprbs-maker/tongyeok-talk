// Firestore's Node Timestamp has seconds/nanoseconds but no compareTo method.
export function compareTimestamps(a, b) {
  return a.seconds - b.seconds || a.nanoseconds - b.nanoseconds;
}
