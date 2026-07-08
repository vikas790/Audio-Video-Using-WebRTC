// Base states for API-driven UI rendering
abstract class ApiRenderState {}

class Ideal extends ApiRenderState {}

class LoadingState extends ApiRenderState {}

class SuccessState<T> extends ApiRenderState {
  SuccessState(this.data);
  final T data;
}

class ErrorState extends ApiRenderState {
  ErrorState(this.message);
  final String message;
}
