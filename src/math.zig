const rl = @import("raylib");

pub fn getTransformMatrix(position: rl.Vector3, scale: rl.Vector3, rotations: rl.Vector3) rl.Matrix {
    const translation_matrix = rl.Matrix.translate(position.x, position.y, position.z);
    const scale_matrix = rl.Matrix.scale(scale.x, scale.y, scale.z);
    const rotation_matrix = rl.Quaternion.toMatrix(
        rl.math.quaternionFromEuler(rotations.x, rotations.y, rotations.z));

    return scale_matrix.multiply(rotation_matrix).multiply(translation_matrix);
}
