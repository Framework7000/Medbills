/// Why a batch's quantity was changed by hand.
enum AdjustReason {
  count('Stock count'),
  damaged('Damaged / broken'),
  expired('Expired, removed'),
  returnedToSupplier('Returned to supplier'),
  other('Other');

  const AdjustReason(this.label);
  final String label;
}

/// Setting a batch's stock to a counted figure (in base units).
class StockAdjustment {
  final int newQuantity;
  final AdjustReason reason;
  final String note;

  const StockAdjustment({required this.newQuantity, required this.reason, this.note = ''});

  List<String> problems() => [
        if (newQuantity < 0) 'Stock cannot be less than zero.',
        if (newQuantity > 10000000) 'That quantity looks wrong.',
        if (reason == AdjustReason.other && note.trim().isEmpty) 'Write a short reason.',
      ];

  String describe(int oldQuantity) =>
      '$oldQuantity → $newQuantity (${reason.label}${note.trim().isEmpty ? '' : ': ${note.trim()}'})';
}
