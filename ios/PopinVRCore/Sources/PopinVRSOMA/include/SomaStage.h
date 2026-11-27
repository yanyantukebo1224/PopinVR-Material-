#ifndef POPINVR_SOMA_STAGE_H
#define POPINVR_SOMA_STAGE_H

#ifdef __cplusplus
extern "C" {
#endif

void *soma_create(
    int V, int J, int F, int K,
    const double *pca_mean, const double *pca_matrix, double rest_scale,
    const double *Wpos, const double *bpos, const int *parents,
    const int *fit_joints, const int *set_off, const int *set_vids,
    const double *p0, const double *R0, const double *bind_shape,
    const int *child_off, const int *child_ids,
    const int *skin_off, const int *skin_j, const double *skin_w,
    const double *bind_local_R, const double *bind_root_t,
    double prior_strength, double rank_threshold, int ns_iters, int skip_endjoints
);

void soma_destroy(void *ctx);

void soma_pose(
    void *ctx, int B, const double *pose, const double *root_t,
    const double *identity, const double *scales,
    double *out_verts, double *out_joints
);

void soma_pose_offsets(
    void *ctx, int B, const double *pose, const double *root_t,
    const double *identity, const double *scales, const double *offsets,
    double *out_verts, double *out_joints
);

#ifdef __cplusplus
}
#endif

#endif
