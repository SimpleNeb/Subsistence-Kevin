// Coordinate serialization uses only stock JsonObject APIs. The comma-separated
// format is compatible with Subsistence's coordinate helpers.
class KevinJson extends Object;

static function SetPosition(JsonObject record, string key, vector position)
{
    record.SetStringValue(key, position.X $ "," $ position.Y $ "," $ position.Z);
}

static function vector GetPosition(JsonObject record, string key)
{
    local array<string> components;
    local vector position;
    ParseStringIntoArray(record.GetStringValue(key), components, ",", false);
    if (components.Length == 3) {
        position.X = float(components[0]);
        position.Y = float(components[1]);
        position.Z = float(components[2]);
    }
    return position;
}

static function SetRotation(JsonObject record, string key, rotator facing)
{
    record.SetStringValue(key, facing.Pitch $ "," $ facing.Yaw $ "," $ facing.Roll);
}

static function rotator GetRotation(JsonObject record, string key)
{
    local array<string> components;
    local rotator facing;
    ParseStringIntoArray(record.GetStringValue(key), components, ",", false);
    if (components.Length == 3) {
        facing.Pitch = int(components[0]);
        facing.Yaw = int(components[1]);
        facing.Roll = int(components[2]);
    }
    return facing;
}
