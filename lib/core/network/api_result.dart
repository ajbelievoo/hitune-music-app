class ApiResult<T> {
  final T? data;
  final ApiError? error;

  const ApiResult._({this.data, this.error});

  bool get isSuccess => error == null;

  factory ApiResult.success(T data) => ApiResult._(data: data);

  factory ApiResult.failure(ApiError error) => ApiResult._(error: error);
}

class ApiError {
  final String code;
  final String message;
  final int? httpStatus;
  final Object? cause;

  const ApiError({
    required this.code,
    required this.message,
    this.httpStatus,
    this.cause,
  });
}
