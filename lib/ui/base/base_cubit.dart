import 'package:flutter_bloc/flutter_bloc.dart';

// Base cubit for feature-level state management
abstract class BaseCubit<S> extends Cubit<S> {
  BaseCubit(super.initialState);
}
