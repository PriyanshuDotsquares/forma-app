/// XP -> level formula shared by the profile header and the "Level & XP"
/// detail sheet.
///
/// There is no leveling endpoint or documented formula from the backend —
/// `User.xp` is just a running integer — so this is a deliberately simple,
/// flat curve picked for this pass: 100 XP per level, level 1 at 0 XP.
/// If another screen ever renders level/XP too, mirror this formula rather
/// than inventing a second one.
class LevelProgress {
  const LevelProgress({required this.level, required this.xpIntoLevel, required this.xpForNextLevel});

  final int level;
  final int xpIntoLevel;
  final int xpForNextLevel;

  double get fraction => xpForNextLevel <= 0 ? 0 : (xpIntoLevel / xpForNextLevel).clamp(0, 1).toDouble();

  factory LevelProgress.fromXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    return LevelProgress(level: safeXp ~/ 100 + 1, xpIntoLevel: safeXp % 100, xpForNextLevel: 100);
  }
}
