import 'package:uuid/uuid.dart';

String newId() => const Uuid().v4();

/// Normalizes persisted status values ('ACTIVE', ' Paid ', etc.) to canonical
/// lowercase so status comparisons never fail on legacy/imported data.
String _status(dynamic j, String fallback) {
  final v = j is Map ? j['status'] : null;
  return v == null ? fallback : v.toString().trim().toLowerCase();
}

/// Normalizes persisted enum-like strings (e.g. zakat `type`) so legacy or
/// imported casing/whitespace cannot make a record invisible.
String _normalizedValue(dynamic value, String fallback) {
  final v = value?.toString().trim().toLowerCase();
  return (v == null || v.isEmpty) ? fallback : v;
}

/// Safe numeric, boolean, and map coercion helpers for robust JSON deserialization.
double _toDouble(dynamic v, [double defaultValue = 0.0]) {
  if (v == null) return defaultValue;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? defaultValue;
  return defaultValue;
}

double? _toNullableDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int _toInt(dynamic v, [int defaultValue = 0]) {
  if (v == null) return defaultValue;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? defaultValue;
  return defaultValue;
}

bool _toBool(dynamic v, [bool defaultValue = false]) {
  if (v == null) return defaultValue;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final lower = v.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return defaultValue;
}

Map<String, dynamic> _s(dynamic j) {
  if (j is Map<String, dynamic>) return j;
  if (j is Map) return Map<String, dynamic>.from(j);
  return <String, dynamic>{};
}

class PropertyManager {
  final String id, name, address, phone, email;
  final String? avatar,
      propertyName,
      ownerName,
      city,
      state,
      zipCode,
      updatedAt;
  final List<String> propertyPictures;
  PropertyManager({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.email,
    this.avatar,
    this.propertyName,
    this.ownerName,
    this.city,
    this.state,
    this.zipCode,
    this.updatedAt,
    this.propertyPictures = const [],
  });
  factory PropertyManager.fromJson(Map<String, dynamic> j) => PropertyManager(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    address: j['address'] ?? '',
    phone: j['phone'] ?? '',
    email: j['email'] ?? '',
    avatar: j['avatar'],
    propertyName: j['propertyName'],
    ownerName: j['ownerName'],
    city: j['city'],
    state: j['state'],
    zipCode: j['zipCode'],
    updatedAt: j['updatedAt']?.toString(),
    propertyPictures: List<String>.from(j['propertyPictures'] ?? []),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'phone': phone,
    'email': email,
    'avatar': avatar,
    'propertyName': propertyName,
    'ownerName': ownerName,
    'city': city,
    'state': state,
    'zipCode': zipCode,
    'updatedAt': updatedAt,
    'propertyPictures': propertyPictures,
  };
  PropertyManager copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? avatar,
    String? propertyName,
    String? ownerName,
    String? updatedAt,
    List<String>? propertyPictures,
  }) => PropertyManager(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    avatar: avatar ?? this.avatar,
    propertyName: propertyName ?? this.propertyName,
    ownerName: ownerName ?? this.ownerName,
    city: city,
    state: state,
    zipCode: zipCode,
    updatedAt: updatedAt ?? this.updatedAt,
    propertyPictures: propertyPictures ?? this.propertyPictures,
  );
}

class Property {
  final String id;
  final String name;
  final String address;
  final String propertyType; // 'residential', 'commercial', 'mixed', 'villa'
  final int totalUnits;
  final String? imagePath;
  final String? notes;
  final String? updatedAt;
  final DateTime createdAt;

  const Property({
    required this.id,
    required this.name,
    required this.address,
    this.propertyType = 'residential',
    this.totalUnits = 1,
    this.imagePath,
    this.notes,
    this.updatedAt,
    required this.createdAt,
  });

  factory Property.fromJson(Map<String, dynamic> j) {
    final name = '${j['name'] ?? 'Primary Property'}';
    final address = '${j['address'] ?? ''}';
    final rawId = j['id']?.toString() ?? '';
    // Legacy backups may omit the id. Use a deterministic id derived from the
    // content instead of generating a new random one on every load, otherwise
    // tenants/payments referencing the persisted id become orphaned.
    final fallbackId =
        'prop-${((name + address).hashCode & 0x7fffffff).toRadixString(16)}';
    return Property(
      id: (rawId.isEmpty || rawId == 'null') ? fallbackId : rawId,
      name: name,
      address: address,
      propertyType: '${j['propertyType'] ?? 'residential'}',
      totalUnits: _toInt(j['totalUnits'], 1),
      imagePath: j['imagePath']?.toString(),
      notes: j['notes']?.toString(),
      updatedAt: j['updatedAt']?.toString() ?? j['createdAt']?.toString(),
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'propertyType': propertyType,
    'totalUnits': totalUnits,
    'imagePath': imagePath,
    'notes': notes,
    'updatedAt': updatedAt ?? createdAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  Property copyWith({
    String? id,
    String? name,
    String? address,
    String? propertyType,
    int? totalUnits,
    String? imagePath,
    String? notes,
    String? updatedAt,
    DateTime? createdAt,
  }) => Property(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address ?? this.address,
    propertyType: propertyType ?? this.propertyType,
    totalUnits: totalUnits ?? this.totalUnits,
    imagePath: imagePath ?? this.imagePath,
    notes: notes ?? this.notes,
    updatedAt: updatedAt ?? this.updatedAt,
    createdAt: createdAt ?? this.createdAt,
  );
}

class TenantDocument {
  final String id, name, uri, type, uploadedAt;
  TenantDocument({
    required this.id,
    required this.name,
    required this.uri,
    required this.type,
    required this.uploadedAt,
  });
  factory TenantDocument.fromJson(Map<String, dynamic> j) => TenantDocument(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    uri: j['uri'] ?? '',
    type: j['type'] ?? 'other',
    uploadedAt: j['uploadedAt'] ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uri': uri,
    'type': type,
    'uploadedAt': uploadedAt,
  };
}

class Tenant {
  final String id, name, unit, phone, email, status, joinDate, propertyId;
  final double rentAmount;
  final double? deposit, advancePaymentAmount;
  final String? avatar,
      fathersName,
      address,
      idNumber,
      dateOfBirth,
      gasMeterNumber,
      electricMeterNumber,
      advancePaymentMonth,
      leaseStartDate,
      leaseEndDate;
  final List<TenantDocument> documents;
  final String? updatedAt;
  Tenant({
    required this.id,
    required this.name,
    required this.unit,
    required this.phone,
    required this.email,
    required this.rentAmount,
    this.status = 'active',
    required this.joinDate,
    this.propertyId = 'prop-default',
    this.deposit,
    this.avatar,
    this.fathersName,
    this.address,
    this.idNumber,
    this.dateOfBirth,
    this.gasMeterNumber,
    this.electricMeterNumber,
    this.documents = const [],
    this.advancePaymentAmount,
    this.advancePaymentMonth,
    this.leaseStartDate,
    this.leaseEndDate,
    this.updatedAt,
  });
  factory Tenant.fromJson(Map<String, dynamic> j) {
    final rawDocs = j['documents'];
    final docs = <TenantDocument>[];
    if (rawDocs is List) {
      for (final d in rawDocs) {
        try {
          if (d is Map) docs.add(TenantDocument.fromJson(_s(d)));
        } catch (_) {}
      }
    }
    return Tenant(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      unit: '${j['unit'] ?? ''}',
      phone: '${j['phone'] ?? ''}',
      email: '${j['email'] ?? ''}',
      rentAmount: _toDouble(j['rentAmount']),
      status: _status(j, 'active'),
      joinDate: '${j['joinDate'] ?? ''}',
      propertyId: j['propertyId']?.toString().isNotEmpty == true
          ? j['propertyId'].toString()
          : 'prop-default',
      deposit: _toNullableDouble(j['deposit']),
      avatar: j['avatar']?.toString(),
      fathersName: j['fathersName']?.toString(),
      address: j['address']?.toString(),
      idNumber: j['idNumber']?.toString(),
      dateOfBirth: j['dateOfBirth']?.toString(),
      gasMeterNumber: j['gasMeterNumber']?.toString(),
      electricMeterNumber: j['electricMeterNumber']?.toString(),
      documents: docs,
      advancePaymentAmount: _toNullableDouble(j['advancePaymentAmount']),
      advancePaymentMonth: j['advancePaymentMonth']?.toString(),
      leaseStartDate: j['leaseStartDate']?.toString(),
      leaseEndDate: j['leaseEndDate']?.toString(),
      updatedAt: j['updatedAt']?.toString() ?? j['joinDate']?.toString(),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'phone': phone,
    'email': email,
    'rentAmount': rentAmount,
    'status': status,
    'joinDate': joinDate,
    'propertyId': propertyId,
    'deposit': deposit,
    'avatar': avatar,
    'fathersName': fathersName,
    'address': address,
    'idNumber': idNumber,
    'dateOfBirth': dateOfBirth,
    'gasMeterNumber': gasMeterNumber,
    'electricMeterNumber': electricMeterNumber,
    'documents': documents.map((e) => e.toJson()).toList(),
    'advancePaymentAmount': advancePaymentAmount,
    'advancePaymentMonth': advancePaymentMonth,
    'leaseStartDate': leaseStartDate,
    'leaseEndDate': leaseEndDate,
    'updatedAt': updatedAt ?? joinDate,
  };
  Tenant copyWith({
    String? name,
    String? unit,
    String? phone,
    String? email,
    double? rentAmount,
    String? status,
    String? joinDate,
    String? avatar,
    List<TenantDocument>? documents,
    double? deposit,
    String? fathersName,
    String? address,
    String? idNumber,
    String? dateOfBirth,
    String? gasMeterNumber,
    String? electricMeterNumber,
    double? advancePaymentAmount,
    String? advancePaymentMonth,
    String? leaseStartDate,
    String? leaseEndDate,
    String? propertyId,
    String? updatedAt,
  }) => Tenant(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    rentAmount: rentAmount ?? this.rentAmount,
    status: status ?? this.status,
    joinDate: joinDate ?? this.joinDate,
    propertyId: propertyId ?? this.propertyId,
    deposit: deposit ?? this.deposit,
    avatar: avatar ?? this.avatar,
    fathersName: fathersName ?? this.fathersName,
    address: address ?? this.address,
    idNumber: idNumber ?? this.idNumber,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    gasMeterNumber: gasMeterNumber ?? this.gasMeterNumber,
    electricMeterNumber: electricMeterNumber ?? this.electricMeterNumber,
    documents: documents ?? this.documents,
    advancePaymentAmount: advancePaymentAmount ?? this.advancePaymentAmount,
    advancePaymentMonth: advancePaymentMonth ?? this.advancePaymentMonth,
    leaseStartDate: leaseStartDate ?? this.leaseStartDate,
    leaseEndDate: leaseEndDate ?? this.leaseEndDate,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class Payment {
  final String id, tenantId, status;
  final double amount;
  final String? dueDate,
      paidDate,
      paidForMonth,
      paymentMonthName,
      displayMonth,
      notes,
      propertyId,
      updatedAt;
  Payment({
    required this.id,
    required this.tenantId,
    required this.amount,
    this.status = 'pending',
    this.dueDate,
    this.paidDate,
    this.paidForMonth,
    this.paymentMonthName,
    this.displayMonth,
    this.notes,
    this.propertyId = 'prop-default',
    this.updatedAt,
  });
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: '${j['id'] ?? ''}',
    tenantId: '${j['tenantId'] ?? ''}',
    amount: _toDouble(j['amount']),
    status: _status(j, 'pending'),
    dueDate: j['dueDate']?.toString(),
    paidDate: j['paidDate']?.toString(),
    paidForMonth: j['paidForMonth']?.toString(),
    paymentMonthName: j['paymentMonthName']?.toString(),
    displayMonth: j['displayMonth']?.toString(),
    notes: j['notes']?.toString(),
    propertyId: j['propertyId']?.toString() ?? 'prop-default',
    updatedAt:
        j['updatedAt']?.toString() ??
        j['paidDate']?.toString() ??
        j['dueDate']?.toString(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'tenantId': tenantId,
    'amount': amount,
    'status': status,
    'dueDate': dueDate,
    'paidDate': paidDate,
    'paidForMonth': paidForMonth,
    'paymentMonthName': paymentMonthName,
    'displayMonth': displayMonth,
    'notes': notes,
    'propertyId': propertyId,
    'updatedAt': updatedAt ?? paidDate ?? dueDate,
  };
  Payment copyWith({
    String? id,
    String? tenantId,
    String? status,
    double? amount,
    String? dueDate,
    String? paidDate,
    String? paidForMonth,
    String? paymentMonthName,
    String? displayMonth,
    String? notes,
    String? propertyId,
    String? updatedAt,
  }) => Payment(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,
    amount: amount ?? this.amount,
    status: status ?? this.status,
    dueDate: dueDate ?? this.dueDate,
    paidDate: paidDate ?? this.paidDate,
    paidForMonth: paidForMonth ?? this.paidForMonth,
    paymentMonthName: paymentMonthName ?? this.paymentMonthName,
    displayMonth: displayMonth ?? this.displayMonth,
    notes: notes ?? this.notes,
    propertyId: propertyId ?? this.propertyId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class Expense {
  final String id, category, description, date, status;
  final double amount;
  final String? paidDate,
      expenseForMonth,
      displayMonth,
      receipt,
      propertyId,
      updatedAt;
  final List<String> receiptFiles;
  Expense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    this.status = 'paid',
    this.paidDate,
    this.expenseForMonth,
    this.displayMonth,
    this.receipt,
    this.propertyId = 'prop-default',
    this.receiptFiles = const [],
    this.updatedAt,
  });
  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: '${j['id'] ?? ''}',
    category: '${j['category'] ?? ''}',
    description: '${j['description'] ?? ''}',
    amount: _toDouble(j['amount']),
    date: '${j['date'] ?? ''}',
    status: _status(j, 'paid'),
    paidDate: j['paidDate']?.toString(),
    expenseForMonth: j['expenseForMonth']?.toString(),
    displayMonth: j['displayMonth']?.toString(),
    receipt: j['receipt']?.toString(),
    propertyId: j['propertyId']?.toString() ?? 'prop-default',
    receiptFiles: (j['receiptFiles'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    updatedAt:
        j['updatedAt']?.toString() ??
        j['paidDate']?.toString() ??
        j['date']?.toString(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'description': description,
    'amount': amount,
    'date': date,
    'status': status,
    'paidDate': paidDate,
    'expenseForMonth': expenseForMonth,
    'displayMonth': displayMonth,
    'receipt': receipt,
    'propertyId': propertyId,
    'receiptFiles': receiptFiles,
    'updatedAt': updatedAt ?? paidDate ?? date,
  };
  Expense copyWith({
    String? id,
    String? category,
    String? description,
    String? date,
    String? status,
    double? amount,
    String? paidDate,
    String? expenseForMonth,
    String? displayMonth,
    String? receipt,
    String? propertyId,
    List<String>? receiptFiles,
    String? updatedAt,
  }) => Expense(
    id: id ?? this.id,
    category: category ?? this.category,
    description: description ?? this.description,
    date: date ?? this.date,
    status: status ?? this.status,
    amount: amount ?? this.amount,
    paidDate: paidDate ?? this.paidDate,
    expenseForMonth: expenseForMonth ?? this.expenseForMonth,
    displayMonth: displayMonth ?? this.displayMonth,
    receipt: receipt ?? this.receipt,
    propertyId: propertyId ?? this.propertyId,
    receiptFiles: receiptFiles ?? this.receiptFiles,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class ExpenseCategory {
  final String id, name, description, color, icon, createdAt, updatedAt;
  final bool isDefault;
  final List<String> suggestedDescriptions;
  ExpenseCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.suggestedDescriptions = const [],
  });
  factory ExpenseCategory.fromJson(Map<String, dynamic> j) => ExpenseCategory(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    description: '${j['description'] ?? ''}',
    color: '${j['color'] ?? '#4CAF50'}',
    icon: '${j['icon'] ?? 'pricetag'}',
    isDefault: _toBool(j['isDefault'], false),
    createdAt: '${j['createdAt'] ?? ''}',
    updatedAt: '${j['updatedAt'] ?? ''}',
    suggestedDescriptions: (j['suggestedDescriptions'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'color': color,
    'icon': icon,
    'isDefault': isDefault,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'suggestedDescriptions': suggestedDescriptions,
  };

  ExpenseCategory copyWith({
    String? id,
    String? name,
    String? description,
    String? color,
    String? icon,
    bool? isDefault,
    String? createdAt,
    String? updatedAt,
    List<String>? suggestedDescriptions,
  }) => ExpenseCategory(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    suggestedDescriptions: suggestedDescriptions ?? this.suggestedDescriptions,
  );
}

class ZakatTransaction {
  final String id, type, date;
  final double amount;
  final String? description, category, receiptUri, propertyId, updatedAt;
  ZakatTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.description,
    this.category,
    this.receiptUri,
    this.propertyId,
    this.updatedAt,
  });
  factory ZakatTransaction.fromJson(Map<String, dynamic> j) => ZakatTransaction(
    id: '${j['id'] ?? ''}',
    type: _normalizedValue(j['type'], 'inflow'),
    amount: _toDouble(j['amount']),
    date: '${j['date'] ?? ''}',
    description: j['description']?.toString(),
    category: j['category']?.toString(),
    receiptUri: j['receiptUri']?.toString(),
    propertyId: j['propertyId']?.toString(),
    updatedAt: j['updatedAt']?.toString() ?? j['date']?.toString(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'amount': amount,
    'date': date,
    'description': description,
    'category': category,
    'receiptUri': receiptUri,
    'propertyId': propertyId,
    'updatedAt': updatedAt ?? date,
  };
  ZakatTransaction copyWith({String? propertyId, String? updatedAt}) =>
      ZakatTransaction(
        id: id,
        type: type,
        amount: amount,
        date: date,
        description: description,
        category: category,
        receiptUri: receiptUri,
        propertyId: propertyId ?? this.propertyId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ZakatCategory {
  final String id, name, icon, color, description, type;
  final bool isDefault;
  ZakatCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    this.isDefault = false,
    this.type = 'both',
  });
  factory ZakatCategory.fromJson(Map<String, dynamic> j) => ZakatCategory(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    icon: '${j['icon'] ?? 'heart'}',
    color: '${j['color'] ?? '#4CAF50'}',
    description: '${j['description'] ?? ''}',
    isDefault: _toBool(j['isDefault'], false),
    type: '${j['type'] ?? 'both'}',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'description': description,
    'isDefault': isDefault,
    'type': type,
  };
}

const kWorkOrderCategories = [
  'Plumbing',
  'Electrical',
  'HVAC',
  'Carpentry',
  'Painting',
  'Flooring',
  'Roofing',
  'Appliances',
  'Security',
  'Landscaping',
  'Cleaning',
  'General Maintenance',
  'Emergency Repair',
  'Other',
];

class WorkOrder {
  final String id,
      title,
      description,
      status,
      category,
      assignedTo,
      createdAt,
      dueDate;
  final String? unit,
      receipt,
      tenantId,
      priority,
      completedAt,
      propertyId,
      updatedAt;
  final double? productPrice, workerCost;
  WorkOrder({
    required this.id,
    required this.title,
    required this.description,
    this.status = 'pending',
    this.category = 'General Maintenance',
    required this.assignedTo,
    required this.createdAt,
    required this.dueDate,
    this.unit,
    this.productPrice,
    this.workerCost,
    this.receipt,
    this.tenantId,
    this.priority,
    this.completedAt,
    this.propertyId = 'prop-default',
    this.updatedAt,
  });
  factory WorkOrder.fromJson(Map<String, dynamic> j) => WorkOrder(
    id: '${j['id'] ?? ''}',
    title: '${j['title'] ?? ''}',
    description: '${j['description'] ?? ''}',
    status: _status(j, 'pending'),
    category: '${j['category'] ?? 'General Maintenance'}',
    assignedTo: '${j['assignedTo'] ?? ''}',
    createdAt: '${j['createdAt'] ?? ''}',
    dueDate: '${j['dueDate'] ?? ''}',
    unit: j['unit']?.toString(),
    productPrice: _toNullableDouble(j['productPrice']),
    workerCost: _toNullableDouble(j['workerCost']),
    receipt: j['receipt']?.toString(),
    tenantId: j['tenantId']?.toString(),
    priority: j['priority']?.toString(),
    completedAt: j['completedAt']?.toString(),
    propertyId: j['propertyId']?.toString() ?? 'prop-default',
    updatedAt:
        j['updatedAt']?.toString() ??
        j['completedAt']?.toString() ??
        j['createdAt']?.toString(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'status': status,
    'category': category,
    'assignedTo': assignedTo,
    'createdAt': createdAt,
    'dueDate': dueDate,
    'unit': unit,
    'productPrice': productPrice,
    'workerCost': workerCost,
    'receipt': receipt,
    'tenantId': tenantId,
    'priority': priority,
    'completedAt': completedAt,
    'propertyId': propertyId,
    'updatedAt': updatedAt ?? completedAt ?? createdAt,
  };

  WorkOrder copyWith({
    String? id,
    String? title,
    String? description,
    String? status,
    String? category,
    String? assignedTo,
    String? createdAt,
    String? dueDate,
    String? unit,
    double? productPrice,
    double? workerCost,
    String? receipt,
    String? tenantId,
    String? priority,
    String? completedAt,
    String? propertyId,
    String? updatedAt,
    bool clearCompletedAt = false,
  }) => WorkOrder(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    category: category ?? this.category,
    assignedTo: assignedTo ?? this.assignedTo,
    createdAt: createdAt ?? this.createdAt,
    dueDate: dueDate ?? this.dueDate,
    unit: unit ?? this.unit,
    productPrice: productPrice ?? this.productPrice,
    workerCost: workerCost ?? this.workerCost,
    receipt: receipt ?? this.receipt,
    tenantId: tenantId ?? this.tenantId,
    priority: priority ?? this.priority,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    propertyId: propertyId ?? this.propertyId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class BankInfo {
  final String id, name;
  final String? logo, accountNumber, routingNumber, updatedAt;
  final bool isDefault;
  BankInfo({
    required this.id,
    required this.name,
    this.logo,
    this.accountNumber,
    this.routingNumber,
    this.updatedAt,
    this.isDefault = false,
  });
  factory BankInfo.fromJson(Map<String, dynamic> j) => BankInfo(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    logo: j['logo']?.toString(),
    accountNumber: j['accountNumber']?.toString(),
    routingNumber: j['routingNumber']?.toString(),
    updatedAt: j['updatedAt']?.toString(),
    isDefault: _toBool(j['isDefault'], false),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'logo': logo,
    'accountNumber': accountNumber,
    'routingNumber': routingNumber,
    'updatedAt': updatedAt,
    'isDefault': isDefault,
  };
  BankInfo copyWith({
    String? id,
    String? name,
    String? logo,
    String? accountNumber,
    String? routingNumber,
    String? updatedAt,
    bool? isDefault,
  }) => BankInfo(
    id: id ?? this.id,
    name: name ?? this.name,
    logo: logo ?? this.logo,
    accountNumber: accountNumber ?? this.accountNumber,
    routingNumber: routingNumber ?? this.routingNumber,
    updatedAt: updatedAt ?? this.updatedAt,
    isDefault: isDefault ?? this.isDefault,
  );
}

class BankDeposit {
  final String id, bankId, bankName, depositDate, description, status;
  final double amount;
  final List<String> linkedPaymentIds;
  final String? bankLogo,
      receiptImage,
      referenceNumber,
      notes,
      updatedAt,
      propertyId;
  BankDeposit({
    required this.id,
    required this.bankId,
    required this.bankName,
    required this.amount,
    required this.depositDate,
    required this.description,
    this.status = 'pending',
    this.bankLogo,
    this.receiptImage,
    this.referenceNumber,
    this.notes,
    this.updatedAt,
    this.propertyId,
    this.linkedPaymentIds = const [],
  });
  factory BankDeposit.fromJson(Map<String, dynamic> j) => BankDeposit(
    id: '${j['id'] ?? ''}',
    bankId: '${j['bankId'] ?? ''}',
    bankName: '${j['bankName'] ?? ''}',
    amount: j['amount'] is num
        ? (j['amount'] as num).toDouble()
        : (double.tryParse('${j['amount'] ?? '0'}') ?? 0.0),
    depositDate: '${j['depositDate'] ?? ''}',
    description: '${j['description'] ?? ''}',
    status: _status(j, 'pending'),
    bankLogo: j['bankLogo']?.toString(),
    receiptImage: j['receiptImage']?.toString(),
    referenceNumber: j['referenceNumber']?.toString(),
    notes: j['notes']?.toString(),
    updatedAt: j['updatedAt']?.toString() ?? j['depositDate']?.toString(),
    propertyId: j['propertyId']?.toString(),
    linkedPaymentIds:
        (j['linkedPaymentIds'] as List?)
            ?.map((e) => '$e')
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [],
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'bankId': bankId,
    'bankName': bankName,
    'amount': amount,
    'depositDate': depositDate,
    'description': description,
    'status': status,
    'bankLogo': bankLogo,
    'receiptImage': receiptImage,
    'referenceNumber': referenceNumber,
    'notes': notes,
    'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
    if (propertyId != null) 'propertyId': propertyId,
    if (linkedPaymentIds.isNotEmpty) 'linkedPaymentIds': linkedPaymentIds,
  };

  BankDeposit copyWith({
    String? id,
    String? bankId,
    String? bankName,
    double? amount,
    String? depositDate,
    String? description,
    String? status,
    String? bankLogo,
    String? receiptImage,
    String? referenceNumber,
    String? notes,
    String? updatedAt,
    String? propertyId,
    List<String>? linkedPaymentIds,
  }) => BankDeposit(
    id: id ?? this.id,
    bankId: bankId ?? this.bankId,
    bankName: bankName ?? this.bankName,
    amount: amount ?? this.amount,
    depositDate: depositDate ?? this.depositDate,
    description: description ?? this.description,
    status: status ?? this.status,
    bankLogo: bankLogo ?? this.bankLogo,
    receiptImage: receiptImage ?? this.receiptImage,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    notes: notes ?? this.notes,
    updatedAt: updatedAt ?? this.updatedAt,
    propertyId: propertyId ?? this.propertyId,
    linkedPaymentIds: linkedPaymentIds ?? this.linkedPaymentIds,
  );
}

class RentDoc {
  final String id,
      title,
      type,
      fileName,
      fileSize,
      uploadedBy,
      uploadedDate,
      status;
  final String? unit,
      tenant,
      fileUri,
      description,
      groupId,
      thumbnailUri,
      expiryDate,
      version,
      priority,
      propertyId,
      updatedAt;
  final List<String> tags;
  final bool isPdf;
  final int pageCount;
  RentDoc({
    required this.id,
    required this.title,
    required this.type,
    required this.fileName,
    required this.fileSize,
    required this.uploadedBy,
    required this.uploadedDate,
    this.status = 'active',
    this.unit,
    this.tenant,
    this.fileUri,
    this.description,
    this.groupId,
    this.thumbnailUri,
    this.expiryDate,
    this.version,
    this.priority,
    this.propertyId = 'prop-default',
    this.tags = const [],
    this.isPdf = false,
    this.pageCount = 0,
    this.updatedAt,
  });
  factory RentDoc.fromJson(Map<String, dynamic> j) => RentDoc(
    id: '${j['id'] ?? ''}',
    title: '${j['title'] ?? ''}',
    type: '${j['type'] ?? 'other'}',
    fileName: '${j['fileName'] ?? ''}',
    fileSize: '${j['fileSize'] ?? ''}',
    uploadedBy: '${j['uploadedBy'] ?? ''}',
    uploadedDate: '${j['uploadedDate'] ?? ''}',
    status: _status(j, 'active'),
    unit: j['unit']?.toString(),
    tenant: j['tenant']?.toString(),
    fileUri: j['fileUri']?.toString(),
    description: j['description']?.toString(),
    groupId: j['groupId']?.toString(),
    thumbnailUri: j['thumbnailUri']?.toString(),
    expiryDate: j['expiryDate']?.toString(),
    version: j['version']?.toString(),
    priority: j['priority']?.toString(),
    propertyId: j['propertyId']?.toString() ?? 'prop-default',
    tags: (j['tags'] as List? ?? []).map((e) => e.toString()).toList(),
    isPdf: _toBool(j['isPdf'], false),
    pageCount: _toInt(j['pageCount'], 0),
    updatedAt: j['updatedAt']?.toString() ?? j['uploadedDate']?.toString(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'fileName': fileName,
    'fileSize': fileSize,
    'uploadedBy': uploadedBy,
    'uploadedDate': uploadedDate,
    'status': status,
    'unit': unit,
    'tenant': tenant,
    'fileUri': fileUri,
    'description': description,
    'groupId': groupId,
    'thumbnailUri': thumbnailUri,
    'expiryDate': expiryDate,
    'version': version,
    'priority': priority,
    'propertyId': propertyId,
    'tags': tags,
    'isPdf': isPdf,
    'pageCount': pageCount,
    'updatedAt': updatedAt ?? uploadedDate,
  };
  RentDoc copyWith({
    String? id,
    String? title,
    String? type,
    String? fileName,
    String? fileSize,
    String? uploadedBy,
    String? uploadedDate,
    String? status,
    String? unit,
    String? tenant,
    String? fileUri,
    String? description,
    String? groupId,
    String? thumbnailUri,
    String? expiryDate,
    String? version,
    String? priority,
    String? propertyId,
    String? updatedAt,
    List<String>? tags,
    bool? isPdf,
    int? pageCount,
  }) => RentDoc(
    id: id ?? this.id,
    title: title ?? this.title,
    type: type ?? this.type,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    uploadedBy: uploadedBy ?? this.uploadedBy,
    uploadedDate: uploadedDate ?? this.uploadedDate,
    status: status ?? this.status,
    unit: unit ?? this.unit,
    tenant: tenant ?? this.tenant,
    fileUri: fileUri ?? this.fileUri,
    description: description ?? this.description,
    groupId: groupId ?? this.groupId,
    thumbnailUri: thumbnailUri ?? this.thumbnailUri,
    expiryDate: expiryDate ?? this.expiryDate,
    version: version ?? this.version,
    priority: priority ?? this.priority,
    propertyId: propertyId ?? this.propertyId,
    tags: tags ?? this.tags,
    isPdf: isPdf ?? this.isPdf,
    pageCount: pageCount ?? this.pageCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class DocumentGroup {
  final String id, title, type, uploadedBy, uploadedDate;
  final String? description, unit, tenant, updatedAt;
  final List<RentDoc> documents;
  final bool isCollapsed;
  DocumentGroup({
    required this.id,
    required this.title,
    required this.type,
    required this.uploadedBy,
    required this.uploadedDate,
    this.description,
    this.unit,
    this.tenant,
    this.updatedAt,
    this.documents = const [],
    this.isCollapsed = false,
  });
  factory DocumentGroup.fromJson(Map<String, dynamic> j) {
    final rawDocs = j['documents'];
    final docs = <RentDoc>[];
    if (rawDocs is List) {
      for (final d in rawDocs) {
        try {
          if (d is Map) docs.add(RentDoc.fromJson(_s(d)));
        } catch (_) {}
      }
    }
    return DocumentGroup(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      type: '${j['type'] ?? 'other'}',
      uploadedBy: '${j['uploadedBy'] ?? ''}',
      uploadedDate: '${j['uploadedDate'] ?? ''}',
      description: j['description']?.toString(),
      unit: j['unit']?.toString(),
      tenant: j['tenant']?.toString(),
      updatedAt: j['updatedAt']?.toString() ?? j['uploadedDate']?.toString(),
      documents: docs,
      isCollapsed: _toBool(j['isCollapsed'], false),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'uploadedBy': uploadedBy,
    'uploadedDate': uploadedDate,
    'description': description,
    'unit': unit,
    'tenant': tenant,
    'updatedAt': updatedAt ?? uploadedDate,
    'documents': documents.map((e) => e.toJson()).toList(),
    'isCollapsed': isCollapsed,
  };
  DocumentGroup copyWith({
    String? id,
    String? title,
    String? type,
    String? uploadedBy,
    String? uploadedDate,
    String? description,
    String? unit,
    String? tenant,
    String? updatedAt,
    List<RentDoc>? documents,
    bool? isCollapsed,
  }) => DocumentGroup(
    id: id ?? this.id,
    title: title ?? this.title,
    type: type ?? this.type,
    uploadedBy: uploadedBy ?? this.uploadedBy,
    uploadedDate: uploadedDate ?? this.uploadedDate,
    description: description ?? this.description,
    unit: unit ?? this.unit,
    tenant: tenant ?? this.tenant,
    updatedAt: updatedAt ?? this.updatedAt,
    documents: documents ?? this.documents,
    isCollapsed: isCollapsed ?? this.isCollapsed,
  );
}

/// Per-tenant document-sync status (Expo `STORAGE_KEYS.TENANT_SYNC_STATUS`).
class TenantSyncStatus {
  String tenantName;
  int totalDocuments;
  int syncedDocuments;
  int failedDocuments;
  bool isSyncing;
  String status; // pending | syncing | completed | failed | partial
  String? lastSyncDate;
  String? lastError;
  TenantSyncStatus({
    required this.tenantName,
    this.totalDocuments = 0,
    this.syncedDocuments = 0,
    this.failedDocuments = 0,
    this.isSyncing = false,
    this.status = 'pending',
    this.lastSyncDate,
    this.lastError,
  });
  factory TenantSyncStatus.fromJson(Map<String, dynamic> j) => TenantSyncStatus(
    tenantName: j['tenantName'] ?? '',
    totalDocuments: j['totalDocuments'] ?? 0,
    syncedDocuments: j['syncedDocuments'] ?? 0,
    failedDocuments: j['failedDocuments'] ?? 0,
    isSyncing: false,
    status: j['status'] ?? 'pending',
    lastSyncDate: j['lastSyncDate'],
    lastError: j['lastError'],
  );
  Map<String, dynamic> toJson() => {
    'tenantName': tenantName,
    'totalDocuments': totalDocuments,
    'syncedDocuments': syncedDocuments,
    'failedDocuments': failedDocuments,
    'status': status,
    'lastSyncDate': lastSyncDate,
    'lastError': lastError,
  };
}

/// Expo `DocumentsScreen` local `getTypeColor` (active palette used by cards/tabs).
const kDocTypeColors = <String, String>{
  'lease': '#4CAF50',
  'invoice': '#4CAF50',
  'maintenance': '#FF9800',
  'legal': '#9C27B0',
  'insurance': '#E91E63',
  'permit': '#795548',
  'inspection': '#607D8B',
  'notice': '#FF5722',
  'id-card': '#9C27B0',
  'contract': '#3F51B5',
  'receipt': '#009688',
  'other': '#607D8B',
};

/// Expo `getTypeIcon` (Ionicons names). `invoice` has no case → `document`.
const kDocTypeIcons = <String, String>{
  'lease': 'document-text',
  'maintenance': 'construct',
  'legal': 'shield-checkmark',
  'insurance': 'shield',
  'permit': 'checkmark-circle',
  'inspection': 'search',
  'notice': 'notifications',
  'id-card': 'id-card',
  'contract': 'business',
  'receipt': 'receipt',
  'other': 'document',
};

/// Expo `getStatusColor` (documents).
const kDocStatusColors = <String, String>{
  'active': '#4CAF50',
  'expired': '#FF6B6B',
  'pending': '#FFB74D',
  'archived': '#9E9E9E',
  'draft': '#FF9800',
};

/// Document type order used by dropdowns / category type picker.
const kDocTypes = <String>[
  'lease',
  'invoice',
  'maintenance',
  'legal',
  'insurance',
  'permit',
  'inspection',
  'notice',
  'id-card',
  'contract',
  'receipt',
  'other',
];

class DocumentCategory {
  final String id, name, type;
  final String? description, color, icon;
  final bool isDefault;
  DocumentCategory({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.color,
    this.icon,
    this.isDefault = false,
  });
  factory DocumentCategory.fromJson(Map<String, dynamic> j) => DocumentCategory(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    type: '${j['type'] ?? 'other'}',
    description: j['description']?.toString(),
    color: j['color']?.toString(),
    icon: j['icon']?.toString(),
    isDefault: _toBool(j['isDefault'], false),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'description': description,
    'color': color,
    'icon': icon,
    'isDefault': isDefault,
  };
}

class AppPreferences {
  final bool showZakat;
  final bool biometricLock;
  final bool autoBackup;
  final String backupSchedule; // 'weekly' | 'monthly'
  final String? lastBackup;
  final bool notifRentDue;
  final bool notifWorkOrder;
  final bool notifExpense;
  final bool notifMaintenance;
  final bool notifDaily;
  final String themeMode; // 'dark' | 'light' | 'system'
  final bool? _driveAutoSync;
  bool get driveAutoSync => _driveAutoSync ?? true;
  final String? _driveSyncFrequency; // 'on_change' | 'daily' | 'weekly'
  String get driveSyncFrequency => _driveSyncFrequency ?? 'on_change';
  final String? lastDriveSync;
  final bool sidebarCollapsed;

  AppPreferences({
    this.showZakat = true,
    this.biometricLock = false,
    this.autoBackup = false,
    this.backupSchedule = 'weekly',
    this.lastBackup,
    this.notifRentDue = true,
    this.notifWorkOrder = true,
    this.notifExpense = true,
    this.notifMaintenance = true,
    this.notifDaily = false,
    this.themeMode = 'dark',
    bool? driveAutoSync = true,
    String? driveSyncFrequency = 'on_change',
    this.lastDriveSync,
    this.sidebarCollapsed = false,
  }) : _driveAutoSync = driveAutoSync ?? true,
       _driveSyncFrequency = driveSyncFrequency ?? 'on_change';

  factory AppPreferences.fromJson(Map<String, dynamic> j) => AppPreferences(
    showZakat: _toBool(j['showZakat'], true),
    biometricLock: _toBool(j['biometricLock'], false),
    autoBackup: _toBool(j['autoBackup'], false),
    backupSchedule: j['backupSchedule']?.toString() ?? 'weekly',
    lastBackup: j['lastBackup']?.toString(),
    notifRentDue: _toBool(j['notifRentDue'], true),
    notifWorkOrder: _toBool(j['notifWorkOrder'], true),
    notifExpense: _toBool(j['notifExpense'], true),
    notifMaintenance: _toBool(j['notifMaintenance'], true),
    notifDaily: _toBool(j['notifDaily'], false),
    themeMode: j['themeMode']?.toString() ?? 'dark',
    driveAutoSync: _toBool(j['driveAutoSync'], true),
    driveSyncFrequency: j['driveSyncFrequency']?.toString() ?? 'on_change',
    lastDriveSync: j['lastDriveSync']?.toString(),
    sidebarCollapsed: _toBool(j['sidebarCollapsed'], false),
  );

  Map<String, dynamic> toJson() => {
    'showZakat': showZakat,
    'biometricLock': biometricLock,
    'autoBackup': autoBackup,
    'backupSchedule': backupSchedule,
    'lastBackup': lastBackup,
    'notifRentDue': notifRentDue,
    'notifWorkOrder': notifWorkOrder,
    'notifExpense': notifExpense,
    'notifMaintenance': notifMaintenance,
    'notifDaily': notifDaily,
    'themeMode': themeMode,
    'driveAutoSync': driveAutoSync,
    'driveSyncFrequency': driveSyncFrequency,
    'lastDriveSync': lastDriveSync,
    'sidebarCollapsed': sidebarCollapsed,
  };

  AppPreferences copyWith({
    bool? showZakat,
    bool? biometricLock,
    bool? autoBackup,
    String? backupSchedule,
    String? lastBackup,
    bool? notifRentDue,
    bool? notifWorkOrder,
    bool? notifExpense,
    bool? notifMaintenance,
    bool? notifDaily,
    String? themeMode,
    bool? driveAutoSync,
    String? driveSyncFrequency,
    String? lastDriveSync,
    bool? sidebarCollapsed,
  }) => AppPreferences(
    showZakat: showZakat ?? this.showZakat,
    biometricLock: biometricLock ?? this.biometricLock,
    autoBackup: autoBackup ?? this.autoBackup,
    backupSchedule: backupSchedule ?? this.backupSchedule,
    lastBackup: lastBackup ?? this.lastBackup,
    notifRentDue: notifRentDue ?? this.notifRentDue,
    notifWorkOrder: notifWorkOrder ?? this.notifWorkOrder,
    notifExpense: notifExpense ?? this.notifExpense,
    notifMaintenance: notifMaintenance ?? this.notifMaintenance,
    notifDaily: notifDaily ?? this.notifDaily,
    themeMode: themeMode ?? this.themeMode,
    driveAutoSync: driveAutoSync ?? this.driveAutoSync,
    driveSyncFrequency: driveSyncFrequency ?? this.driveSyncFrequency,
    lastDriveSync: lastDriveSync ?? this.lastDriveSync,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
  );
}

class MonthlyNote {
  final String id, text, month;
  final bool done;
  final String? propertyId, updatedAt;
  MonthlyNote({
    required this.id,
    required this.text,
    required this.month,
    this.done = false,
    this.propertyId,
    this.updatedAt,
  });
  factory MonthlyNote.fromJson(Map<String, dynamic> j) => MonthlyNote(
    id: '${j['id'] ?? ''}',
    text: '${j['text'] ?? ''}',
    month: '${j['month'] ?? ''}',
    done: _toBool(j['done'], false),
    propertyId: j['propertyId']?.toString(),
    updatedAt: j['updatedAt']?.toString(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'month': month,
    'done': done,
    if (propertyId != null) 'propertyId': propertyId,
    'updatedAt': updatedAt,
  };
  MonthlyNote copyWith({
    String? id,
    String? text,
    String? month,
    bool? done,
    String? propertyId,
    String? updatedAt,
  }) => MonthlyNote(
    id: id ?? this.id,
    text: text ?? this.text,
    month: month ?? this.month,
    done: done ?? this.done,
    propertyId: propertyId ?? this.propertyId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Default seed data — mirrors dataManager.ts defaults.
class DefaultData {
  static List<ExpenseCategory> expenseCategories() {
    const cats = [
      'Maintenance',
      'Utilities',
      'Insurance',
      'Taxes',
      'Repairs',
      'Cleaning',
      'Security',
      'Landscaping',
      'Legal',
      'Management',
      'Supplies',
      'Other',
    ];
    final now = DateTime.now().toIso8601String();
    return cats
        .map(
          (c) => ExpenseCategory(
            id: newId(),
            name: c,
            description: '$c expenses',
            color: '#4CAF50',
            icon: 'pricetag',
            isDefault: true,
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();
  }

  /// Deduplicates expense categories by name (case-insensitive trimmed).
  static List<ExpenseCategory> normalizedExpenseCategories(
    List<ExpenseCategory> stored,
  ) {
    if (stored.isEmpty) return expenseCategories();
    final seen = <String, ExpenseCategory>{};
    for (final c in stored) {
      final key = c.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (!seen.containsKey(key)) {
        seen[key] = c;
      } else {
        final existing = seen[key]!;
        final mergedDescriptions = <String>{
          ...existing.suggestedDescriptions,
          ...c.suggestedDescriptions,
        }.toList();
        seen[key] = existing.copyWith(
          description: existing.description.isNotEmpty
              ? existing.description
              : c.description,
          color: existing.color.isNotEmpty ? existing.color : c.color,
          icon: existing.icon.isNotEmpty ? existing.icon : c.icon,
          isDefault: existing.isDefault || c.isDefault,
          suggestedDescriptions: mergedDescriptions,
        );
      }
    }
    return seen.values.toList();
  }

  /// Default document categories — mirrors `DEFAULT_DOCUMENT_CATEGORIES`
  /// in `dataManager.ts` (name/type/description/color/icon).
  static List<DocumentCategory> documentCategories() => [
    DocumentCategory(
      id: '1',
      name: 'Lease',
      type: 'lease',
      description: 'Rental agreements and lease documents',
      color: '#4CAF50',
      icon: 'document-text',
      isDefault: true,
    ),
    DocumentCategory(
      id: '2',
      name: 'Invoice',
      type: 'invoice',
      description: 'Bills and invoices',
      color: '#FF9800',
      icon: 'receipt',
      isDefault: true,
    ),
    DocumentCategory(
      id: '3',
      name: 'Maintenance',
      type: 'maintenance',
      description: 'Maintenance and repair documents',
      color: '#2196F3',
      icon: 'build',
      isDefault: true,
    ),
    DocumentCategory(
      id: '4',
      name: 'Legal',
      type: 'legal',
      description: 'Legal documents and contracts',
      color: '#9C27B0',
      icon: 'shield',
      isDefault: true,
    ),
    DocumentCategory(
      id: '5',
      name: 'Insurance',
      type: 'insurance',
      description: 'Insurance policies and documents',
      color: '#00BCD4',
      icon: 'umbrella',
      isDefault: true,
    ),
    DocumentCategory(
      id: '6',
      name: 'Permit',
      type: 'permit',
      description: 'Permits and licenses',
      color: '#795548',
      icon: 'checkmark-circle',
      isDefault: true,
    ),
    DocumentCategory(
      id: '7',
      name: 'Inspection',
      type: 'inspection',
      description: 'Inspection reports and certificates',
      color: '#607D8B',
      icon: 'search',
      isDefault: true,
    ),
    DocumentCategory(
      id: '8',
      name: 'Notice',
      type: 'notice',
      description: 'Notices and announcements',
      color: '#FF5722',
      icon: 'megaphone',
      isDefault: true,
    ),
    DocumentCategory(
      id: '9',
      name: 'ID Card',
      type: 'id-card',
      description: 'Identification documents',
      color: '#3F51B5',
      icon: 'card',
      isDefault: true,
    ),
    DocumentCategory(
      id: '10',
      name: 'Contract',
      type: 'contract',
      description: 'Contracts and agreements',
      color: '#E91E63',
      icon: 'document',
      isDefault: true,
    ),
    DocumentCategory(
      id: '11',
      name: 'Receipt',
      type: 'receipt',
      description: 'Receipts and payment confirmations',
      color: '#8BC34A',
      icon: 'receipt-outline',
      isDefault: true,
    ),
    DocumentCategory(
      id: '12',
      name: 'Other',
      type: 'other',
      description: 'Other miscellaneous documents',
      color: '#9E9E9E',
      icon: 'folder',
      isDefault: true,
    ),
  ];

  /// Upgrades legacy stored categories (name == type, missing color/icon) to
  /// the rich defaults and deduplicates them so every type/id is strictly unique.
  static List<DocumentCategory> normalizedDocumentCategories(
    List<DocumentCategory> stored,
  ) {
    if (stored.isEmpty) return documentCategories();
    final defaults = {for (final c in documentCategories()) c.type: c};
    final seen = <String, DocumentCategory>{};
    for (final c in stored) {
      final key = c.type.trim().toLowerCase();
      if (key.isEmpty || seen.containsKey(key)) continue;
      final d = defaults[c.type];
      if (d == null) {
        seen[key] = c;
      } else {
        final name = c.name == c.type ? d.name : c.name;
        final color = (c.color == null || c.color!.isEmpty) ? d.color : c.color;
        final icon = (c.icon == null || c.icon!.isEmpty) ? d.icon : c.icon;
        final desc = (c.description == null || c.description!.isEmpty)
            ? d.description
            : c.description;
        seen[key] = DocumentCategory(
          id: c.id,
          name: name,
          type: c.type,
          description: desc,
          color: color,
          icon: icon,
          isDefault: c.isDefault,
        );
      }
    }
    return seen.values.toList();
  }

  /// Deduplicates zakat categories by id or name so all entries are strictly unique.
  static List<ZakatCategory> normalizedZakatCategories(
    List<ZakatCategory> stored,
  ) {
    if (stored.isEmpty) return zakatCategories();
    final seen = <String, ZakatCategory>{};
    for (final c in stored) {
      final key = c.id.trim().toLowerCase().isNotEmpty
          ? c.id.trim().toLowerCase()
          : c.name.trim().toLowerCase();
      if (key.isEmpty || seen.containsKey(key)) continue;
      seen[key] = c;
    }
    return seen.values.toList();
  }

  /// Typed defaults — exact port of `src/utils/zakatData.ts` ZAKAT_CATEGORIES
  /// (outflow causes + inflow sources) with stable ids.
  static List<ZakatCategory> zakatCategories() => [
    for (final e in const [
      [
        'food',
        'Food & Hunger Relief',
        'restaurant',
        '#FF6B6B',
        'Providing food to the needy and hungry',
        'outflow',
        true,
      ],
      [
        'education',
        'Education',
        'school',
        '#4ECDC4',
        'Supporting educational initiatives and students',
        'outflow',
        true,
      ],
      [
        'healthcare',
        'Healthcare',
        'medical',
        '#45B7D1',
        'Medical assistance and healthcare support',
        'outflow',
        true,
      ],
      [
        'orphans',
        'Orphans & Children',
        'people',
        '#96CEB4',
        'Supporting orphaned children and families',
        'outflow',
        true,
      ],
      [
        'mosque',
        'Mosque & Religious',
        'business',
        '#FFEAA7',
        'Mosque maintenance and religious activities',
        'outflow',
        true,
      ],
      [
        'refugees',
        'Refugees & Displaced',
        'home',
        '#DDA0DD',
        'Supporting refugees and displaced families',
        'outflow',
        true,
      ],
      [
        'water',
        'Water & Sanitation',
        'water',
        '#74B9FF',
        'Clean water and sanitation projects',
        'outflow',
        true,
      ],
      [
        'emergency',
        'Emergency Relief',
        'warning',
        '#FD79A8',
        'Emergency assistance and disaster relief',
        'outflow',
        true,
      ],
      [
        'general-outflow',
        'General Charity',
        'heart',
        '#A29BFE',
        'General charitable giving',
        'outflow',
        true,
      ],
      [
        'zakat-received',
        'Zakat Received',
        'arrow-down',
        '#4CAF50',
        'Zakat money received from others',
        'inflow',
        true,
      ],
      [
        'charity-refund',
        'Charity Refund',
        'refresh',
        '#4CAF50',
        'Refund from charity organization',
        'inflow',
        true,
      ],
      [
        'general-inflow',
        'General Income',
        'trending-up',
        '#00C851',
        'Other income from charitable sources',
        'inflow',
        false,
      ],
    ])
      ZakatCategory(
        id: e[0] as String,
        name: e[1] as String,
        icon: e[2] as String,
        color: e[3] as String,
        description: e[4] as String,
        type: e[5] as String,
        isDefault: e[6] as bool,
      ),
  ];

  static List<ZakatCategory> zakatCategoriesFor(String type) =>
      zakatCategories()
          .where((c) => c.type == type || c.type == 'both')
          .toList();

  static const predefinedDescriptions = [
    'Monthly rent collection',
    'Utility bill payment',
    'Maintenance work',
    'Repair cost',
    'Property tax',
    'Insurance premium',
    'Cleaning service',
    'Security service',
    'Legal fees',
    'Miscellaneous',
  ];
}
