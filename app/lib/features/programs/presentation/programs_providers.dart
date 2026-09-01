import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../data/programs_repository.dart';

final programsRepositoryProvider = Provider<ProgramsRepository>((ref) => ProgramsRepository(ref.watch(apiClientProvider)));
