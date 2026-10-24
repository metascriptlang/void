// Port of h3d.col.ObjectCollider: a collider placed by a scene object's world matrix. The matrix
// and its inverse are the same TransformFrame that transformCollider.ms carries, so the queries
// there (localRay, worldHitDistance, localPoint, localSphere, worldSphere, scaledDimension) are
// ObjectCollider's own, hx:15-70; this builds the frame the way Object.getInvPos does.

import { Mat4, inverseAffine } from "../math/math3d";
import { TransformFrame, TransformError, transformFrame } from "./transformCollider";

export enum ObjectColliderError { NonFinite, Singular, NotAffine }

// Object.getInvPos, Object.hx:432-441: `inverse3x4` of the absolute position, which is zero for a
// singular one. Heaps then casts every query through that zero matrix; here it is Singular. An
// object's absolute position always has the column (0, 0, 0, 1), and `inverse3x4` forces it, so a
// matrix without it would be answered by an inverse of a different matrix: NotAffine.
export function objectFrame(absPos: Mat4): Result<TransformFrame, ObjectColliderError> {
	const frame = transformFrame(absPos);
	if (!frame.ok) {
		if (frame.error == TransformError.Singular) {
			return Result.err(ObjectColliderError.Singular);
		}
		return Result.err(ObjectColliderError.NonFinite);
	}
	if (absPos.m14 != 0.0 || absPos.m24 != 0.0 || absPos.m34 != 0.0 || absPos.m44 != 1.0) {
		return Result.err(ObjectColliderError.NotAffine);
	}
	return Result.ok({ mat: absPos, invMat: inverseAffine(absPos) });
}
