// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'walk_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WalkSessionAdapter extends TypeAdapter<WalkSession> {
  @override
  final int typeId = 0;

  @override
  WalkSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WalkSession(
      startTime: fields[0] as DateTime,
      endTime: fields[1] as DateTime,
      stepCount: fields[2] as int,
      averageSpeed: fields[3] as double,
    );
  }

  @override
  void write(BinaryWriter writer, WalkSession obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.startTime)
      ..writeByte(1)
      ..write(obj.endTime)
      ..writeByte(2)
      ..write(obj.stepCount)
      ..writeByte(3)
      ..write(obj.averageSpeed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalkSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
