# SPDX-License-Identifier: GPL-3.0-only
"""Bake deterministic periodic numerical density data, not a painted cloud image."""
from pathlib import Path
import numpy as np
from PIL import Image

N = 64
rng = np.random.default_rng(260620)
grid = np.moveaxis(np.indices((N, N, N), dtype=np.float32), 0, -1) / N

def noise(cells):
    values = rng.random((cells, cells, cells)).astype(np.float32)
    p = grid * cells
    i = np.floor(p).astype(int)
    f = p - i
    u = f*f*f*(f*(f*6-15)+10)
    result = np.zeros((N, N, N), np.float32)
    for x in range(2):
        for y in range(2):
            for z in range(2):
                off = np.array([x,y,z])
                idx = (i + off) % cells
                w = np.prod(np.where(off, u, 1-u), axis=-1)
                result += values[idx[...,0],idx[...,1],idx[...,2]]*w
    return result

def worley(cells):
    points = rng.random((cells,cells,cells,3)).astype(np.float32)
    p = grid*cells
    i = np.floor(p).astype(int)
    f = p-i
    best = np.full((N,N,N), 4.0, np.float32)
    for x in [-1,0,1]:
        for y in [-1,0,1]:
            for z in [-1,0,1]:
                off=np.array([x,y,z])
                idx=(i+off)%cells
                delta=off+points[idx[...,0],idx[...,1],idx[...,2]]-f
                best=np.minimum(best,np.sum(delta*delta,axis=-1))
    return np.clip(1-np.sqrt(best)/1.05,0,1)

large = noise(4)*.65 + noise(8)*.25 + noise(16)*.10
w4, w8, w16 = worley(4), worley(8), worley(16)
# Base has structured lobes; erosion channels remain independent at finer scales.
base = np.clip((large*.65 + w4*.35 - 0.5)*1.8 + 0.5,0,1)
volume = np.stack([base,w8,w16,noise(16)],axis=-1)
# Bend the underlying lattice before baking. Periodic low-frequency displacement
# breaks aligned billow rows without adding texture fetches to cloud rendering.
warp = np.stack([noise(2),noise(3),noise(2)],axis=-1) - 0.5
sample = (grid + warp * 0.18) * N
cell = np.floor(sample).astype(int)
fraction = sample - cell
warped = np.zeros_like(volume)
for x in range(2):
    for y in range(2):
        for z in range(2):
            off = np.array([x,y,z])
            index = (cell + off) % N
            weight = np.prod(np.where(off, fraction, 1-fraction),axis=-1)
            warped += volume[index[...,0],index[...,1],index[...,2]] * weight[...,None]
volume = warped
# Storm cover uses a continuous isotropic field instead of cellular ridges.
# Keep its random stream separate so the established clear-weather RGB remains
# byte-identical. Alpha is already fetched with RGB by every cloud consumer.
storm_rng = np.random.default_rng(211026)
frequency = np.fft.fftfreq(N) * N
kx, ky, kz = np.meshgrid(frequency, frequency, frequency, indexing='ij')
radius2 = kx*kx + ky*ky + kz*kz
def storm_band(width):
    spectrum = np.fft.fftn(storm_rng.standard_normal((N,N,N)))
    spectrum *= np.exp(-0.5 * radius2 / (width*width))
    spectrum[0,0,0] = 0.0
    field = np.fft.ifftn(spectrum).real
    return field / max(field.std(), 1e-8)
# Match the clear base's broad density range: a low-contrast field would keep
# too many weakly occupied ray steps alive instead of empty skips/dense exits.
storm = np.clip(0.495 + storm_band(2.4)*0.1725
                + storm_band(5.5)*0.0525 + storm_band(11.0)*0.018, 0.0, 1.0)
volume[...,3] = storm.astype(np.float32)

# 8x8 horizontal slices, with a periodic one-texel gutter around each slice.
atlas=np.zeros((528,528,4),np.uint8)
for y in range(N):
    tile=np.pad(volume[:,y,:,:],((1,1),(1,1),(0,0)),mode='wrap')
    row,col=divmod(y,8)
    atlas[row*66:(row+1)*66,col*66:(col+1)*66]=np.rint(tile*255).astype(np.uint8)
out=Path(__file__).resolve().parents[1] / 'shaders/textures/cloud_volume.png'
Image.fromarray(atlas).save(out)
out.with_suffix('.png.mcmeta').write_text('{"texture":{"blur":true,"clamp":true}}\n',encoding='utf-8')
print('Volume:',atlas.shape,'range',volume.min(),volume.max(),'bytes',out.stat().st_size)
