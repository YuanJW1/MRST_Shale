function W = addWellEDFM(W, G, rock, cellInx, varargin)
%Insert a well into the simulation model.
%
% SYNOPSIS:
%   W = addWell(W, G, rock, cellInx)
%   W = addWell(W, G, rock, cellInx, 'pn', pv, ...)
%
% REQUIRED PARAMETERS:
%   W       - Well structure or empty if no other wells exist.
%             Updated upon return.
%
%   G       - Grid data structure.
%
%   rock    - Rock data structure.  Must contain valid field `perm`.
%
%   cellInx - Perforated well cells (vector of cell indices or a logical
%             mask with length equal to G.cells.num).
%
% OPTIONAL PARAMETERS:
%   Type -   Well control type. String. Supported values depend on the
%            solver in question. Most solvers support at least two options: 
%              - 'bhp': Controlled by bottom hole pressure (DEFAULT)
%              - 'rate': Controlled by total rate.
%
%   Val    - Well control target value.  Interpretation of this value is
%            dependent upon `Type`.  Default value is 0.  If the well
%            `Type` is 'bhp', then `Val` is given in unit Pascal and if
%            the `Type` is 'rate', then `Val` is given in unit m^3/second.
%
%   Radius - Well bore radius (in unit of meters).  Either a single,
%            scalar value which applies to all perforations or a vector of
%            radii (one radius value for each perforation).
%            Default value: Radius = 0.1 (i.e., 10 cm).
%
%   Dir    - Well direction.  Single CHAR or CHAR array.  A single CHAR
%            applies to all perforations while a CHAR array defines the
%            direction of the corresponding perforation.  In other words,
%            Dir(i) is the direction in perforation cellInx(i) in the CHAR
%            array case.
%
%            Supported values for a single perforation are 'x', 'y', or
%            'z' (case insensitive) meaning the corresponding cell is
%            perforated in the X, Y, or Z direction, respectively.
%            Default value: Dir = 'z' (vertical well).
%
%   InnerProduct - The inner product with which to define the mass matrix.
%            String.  Default value = 'ip_tpf'.
%            Supported values are 'ip_simple', 'ip_tpf', 'ip_quasitpf',
%            and 'ip_rt'.
%
%   rR     - The representative radius for the wells, which is used in the
%            shear thinning calculation when polymer is involved in the
%            simulation.
%
%   WI     - Well productivity index. Vector of length `nc=numel(cellInx)`.
%            Default value: `WI = repmat(-1, [nc, 1])`, whence the
%            productivity index will be computed from available grid block
%            data in grid blocks containing well completions.
%
%   Kh     - Permeability thickness.  Vector of length `nc=numel(cellInx)`.
%            Default value: `Kh = repmat(-1, [nc, 1])`, whence the thickness
%            will be computed from available grid block data in grid
%            blocks containing well completions.
%
%   Skin   - Skin factor for computing effective well bore radius.  Scalar
%            value or vector of length `nc=numel(cellInx)`.
%            Default value: 0.0 (no skin effect).
%
%   Comp_i - Fluid composition for injection wells.  Vector of saturations.
%            Default value:  `Comp_i = [1, 0, 0]` (water injection)
%
%   Sign   - Well type: Production (Sign = -1) or Injection (Sign = 1).
%            Default value: 0 (Undetermined sign. Will be derived from
%            rates if possible).
%
%   Name   - Well name (string).
%            Default value: `sprintf('W%d', numel(W) + 1)`
%
%   refDepth - Reference depth for the well, i.e. the value for which
%            bottom hole pressures are defined.
%
% RETURNS:
%   W - Updated (or freshly created) well structure, each element of which
%       has the following fields:
%         - cells:   Grid cells perforated by this well (== cellInx).
%         - type:    Well control type (== Type).
%         - val:     Target control value (== Val).
%         - r:       Well bore radius (== Radius).
%         - dir:     Well direction (== Dir).
%         - WI:      Well productivity index.
%         - dZ: Displacement of each well perforation measured from
%           'highest' horizontal contact (i.e., the 'TOP' contact with the
%           minimum 'Z' value counted amongst all cells perforated by this
%           well).
%         - name:    Well name (== Name).
%         - compi:   Fluid composition--only used for injectors (== Comp_i).
%         - sign:    Injection (+) or production (-) flag.
%         - status:  Boolean indicating if the well is open or shut.
%         - cstatus: One entry per perforation, indicating if the completion is open.
%         - lims:    Limits for the well. Contains subfields for the types
%           of limits applicable to the well (bhp, rate, orat, ...)
%           Injectors generally have upper limits, while producers have
%           lower limits.
% EXAMPLE:
%   incompTutorialWells
%
% NOTE:
%   Wells in two-dimensional grids are not well defined in terms of
%   computing well indices. However, such wells are often useful for
%   simulation scenarios where the exact value of well indices is not of
%   great importance. For this reason, we make the following approximations
%   when addWell is used to compute e.g. horizontal wells in 2D:
%
%       - K_z is assumed to be the harmonic average of K_x and K_y:
%         K_z = 1/(1/K_x + 1/K_y).
%       - The depth of a grid block is assumed to be unit length (1 meter)
%
%   This generally produces reasonable ranges for the WI field, but it is
%   the user's responsibility to keep these assumptions in mind.
%
% SEE ALSO:
%   `verticalWell`, `addSource`, `addBC`.

%{
Copyright 2009-2017 SINTEF ICT, Applied Mathematics.

This file is part of The MATLAB Reservoir Simulation Toolbox (MRST).

MRST is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MRST is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MRST.  If not, see <http://www.gnu.org/licenses/>.
%}


if ~isempty(W) && ~isfield(W, 'WI'),
   error(msgid('CallingSequence:Changed'), ...
        ['The calling sequence for function ''addWell'' has changed\n', ...
         'Please use\n\tW = addWell(W, G, rock, cellInx, ...)\n', ...
         'from now on.']);
end

mrstNargInCheck(4, [], nargin);
if islogical(cellInx)
    assert(numel(cellInx) == G.cells.num, ...
    'Logical mask does not match number of grid cells.');
    cellInx = find(cellInx);
end
numC = numel(cellInx);


opt = struct('InnerProduct', 'ip_tpf',                     ...
             'Dir'         , 'z',                          ...
             'Name'        , sprintf('W%d', numel(W) + 1), ...
             'Radius'      , 0.1,                          ...
             'Type'        , 'bhp',                        ...
             'Val'         , 0,                            ...
             'Comp_i'      , [1, 0, 0],                    ...
             'WI'          , -1*ones(numC,1),              ...
             'Kh'          , -1*ones(numC,1),              ...
             'Skin'        , zeros(numC, 1),               ...
             'refDepth'    , 0,                            ...
             'lims'        , [],                           ...
             'vfp_index'   , 0,                            ...
             'c'           , [],                           ...
             'Sign'        , 0);

opt = merge_options(opt, varargin{:});

WI = reshape(opt.WI, [], 1);

assert (numel(WI)       == numC, ...
    'Provided WI should be one entry per perforated cell.')
assert (numel(opt.Kh)   == numC, ...
    'Provided Kh should be one entry per perforated cell.')
assert (numel(opt.Skin) == numC || numel(opt.Skin) == 1, ...
    ['Provided Skin should be one entry per perforated cell or a single', ...
    ' entry for all perforated cells']);

if numel(opt.Skin) == 1, opt.Skin = opt.Skin(ones([numC, 1]));  end

% Set reference depth default value.
if isempty(opt.refDepth),
   g_vec = gravity();
   dims  = G.griddim;
   if norm(g_vec(1:dims)) > 0,
      g_vec = g_vec ./ norm(g_vec);
      opt.refDepth = min(G.nodes.coords * g_vec(1:dims)');
   else
      opt.refDepth = 0;
   end
end
ip = opt.InnerProduct;

% Compute the representative radius for the grid block in which the well is
% completed. It is needed for computing the shear rate of the wells.
if(isfield(G,'FracGrid')) %Skip this for EDFM
    re= sqrt(G.fractureAperture .* 1 / pi);
    rR= sqrt(re* opt.Radius);
    rR=ones(length(cellInx),1).*rR;
else
    rR = radiusRep(G, opt.Radius, opt.Dir, reshape(cellInx, [], 1));
end
% Initialize Well index - WI. ---------------------------------------------
% Check if we need to calculate WI or if it is supplied.

%Compute EDFM well-fracture WI


fracCellIdx=find(cellInx>G.Matrix.cells.num);
if(length(fracCellIdx)>0) %We have fracture-well NNC
    GlobalCellIdx=cellInx(fracCellIdx(:));
    WI_fm = wellInx_EDFM(G,opt.Radius,GlobalCellIdx,opt);
    WI(fracCellIdx)=WI_fm;
end

compWI = WI < 0;

if any(compWI) % calculate WI for the cells in compWI
   error('[Error]This function only used for fracture-well interaction!')
   WI(compWI) = wellInx(G, rock, opt.Radius, opt.Dir, ...
                        reshape(cellInx, [], 1), ip, opt, compWI);
end

% Set well sign (injection = 1 or production = -1)
% for bhp wells or rate controlled wells with rate = 0.
if opt.Sign ~= 0,
   if sum(opt.Sign == [-1, 1]) ~= 1,
      error(msgid('Sign:NonUnit'), 'Sign must be -1 or 1');
   end
   if strcmp(opt.Type, 'rate') && (sign(opt.Val) ~= 0) ...
         && (opt.Sign ~= sign(opt.Val)),
      warning(msgid('Sign'), ...
             ['Given sign does not match sign of given value. ', ...
              'Setting w.sign = sign( w.val )']);
      opt.Sign = sign(opt.Val);
   end
else
   if strcmp(opt.Type, 'rate'),
      if opt.Val == 0,
         warning(msgid('Sign'), 'Given value is zero, prod or inj ???');
      else
         opt.Sign = sign(opt.Val);
      end
   end
end

% Add well to well structure. ---------------------------------------------
%
W  = [W; struct('cells'    , cellInx(:),           ...
                'type'     , opt.Type,             ...
                'val'      , opt.Val,              ...
                'r'        , opt.Radius,           ...
                'dir'      , opt.Dir,              ...
                'rR'       , rR,                   ...
                'WI'       , WI,                   ...
                'dZ'       , getDepth(G, cellInx(:))-opt.refDepth, ...
                'name'     , opt.Name,             ...
                'compi'    , opt.Comp_i,           ...
                'refDepth' , opt.refDepth,         ...
                'lims'     , opt.lims,             ...
                'sign'     , opt.Sign,             ...
                'c'        , opt.c,                ...
                'status'   , true,                 ...
                'vfp_index', opt.vfp_index,        ...
                'cstatus'  , true(numC,1))];

if numel(W(end).dir) == 1,
   W(end).dir = repmat(W(end).dir, [numel(W(end).cells), 1]);
end
assert (numel(W(end).dir) == numel(W(end).cells));

%--------------------------------------------------------------------------
% Private helper functions follow
%--------------------------------------------------------------------------

function WI = wellInx_EDFM(G,radius, cells,opt)
%Well index for fracture-Well NNC, Eq. 4.10-11 in Moinfar PhD, 2013

WI=zeros(length(cells),1);
for i=1:length(cells)
    fgnum=findFracGridnum(G,cells(i));
    frac_struct=G.FracGrid.(['Frac',num2str(fgnum)]);
    localCellInx=cells(i)-frac_struct.cells.start+1;
    
    lf=abs(frac_struct.cells.centroids(1,2)...
          -frac_struct.cells.centroids(2,2));
    if G.griddim > 2
        sprintf('Not implement yet');
    else
        hf=G.fractureHeight;
    end
    re=0.14*sqrt(lf^2+hf^2);
    kf=frac_struct.rock.perm(localCellInx);
    wf=G.fractureAperture;
    WI(i)=2*pi*kf*wf/(log(re/radius)+opt.Skin(i));
    2*pi*kf*wf/(log(re/radius)+opt.Skin(i))/(2*pi*kf*wf/log(re/radius))
    WI_mdft=convertTo(WI(i),milli*darcy*ft);
end

   

function WI = wellInx(G, rock, radius, welldir, cells, innerProd, opt, inx)

if(isfield(G,'nodes'))
   [dx, dy, dz] = cellDims(G, cells);
else
   [dx, dy, dz] = cellDimsCG(G, cells);
end
if G.griddim > 2,
   k = permDiag3D(rock, cells);
else
   k = permDiag2D(rock, cells);
   kz = 1./(1./k(:, 1) + 1./k(:, 2));
   k = [k, kz];
end
welldir = lower(welldir);

if numel(welldir) == 1, welldir = welldir(ones([size(k,1), 1])); end
if numel(radius)  == 1, radius  = radius (ones([size(k,1), 1])); end

assert (numel(welldir) == size(k,1));
assert (numel(radius)  == size(k,1));

[d1, d2, ell, k1, k2] = deal(zeros([size(k,1), 1]));

ci = welldir == 'x';
[d1(ci), d2(ci), ell(ci), k1(ci), k2(ci)] = ...
   deal(dy(ci), dz(ci), dx(ci), k(ci,2), k(ci,3));

ci = welldir == 'y';
[d1(ci), d2(ci), ell(ci), k1(ci), k2(ci)] = ...
   deal(dx(ci), dz(ci), dy(ci), k(ci,1), k(ci,3));

ci = welldir == 'z';
[d1(ci), d2(ci), ell(ci), k1(ci), k2(ci)] = ...
   deal(dx(ci), dy(ci), dz(ci), k(ci,1), k(ci,2));

% Table look-up (interpolation) for mimetic or 0.14 for tpf
wc  = wellConstant(d1, d2, innerProd);

re1 = 2 * wc .* sqrt((d1.^2).*sqrt(k2 ./ k1) + ...
                     (d2.^2).*sqrt(k1 ./ k2));
re2 = (k2 ./ k1).^(1/4) + (k1 ./ k2).^(1/4);

re  = reshape(re1 ./ re2, [], 1);
ke  = sqrt(k1 .* k2);

Kh = reshape(opt.Kh, [], 1); i = Kh < 0;
if G.griddim > 2,
   Kh(i) = ell(i) .* ke(i);
else
   Kh(i) =           ke(i);
end

WI = 2 * pi * Kh ./ (log(re ./ radius) + reshape(opt.Skin, [], 1));

if any(WI < 0),
   if any(re < radius)
      error(id('WellRadius'), ...
           ['Equivalent radius in well model smaller than well ', ...
            'radius causing negative well index'].');
   else
      error(id('SkinFactor'), ...
            'Large negative skin factor causing negative well index.');
   end
end

% Only return calculated WI for requested cells
WI = WI(inx);

%--------------------------------------------------------------------------

function wellConst = wellConstant(d1, d2, innerProd)
% table= [ratio mixedWellConstant]
table = [ 1, 0.292; ...
          2, 0.278; ...
          3, 0.262; ...
          4, 0.252; ...
          5, 0.244; ...
          8, 0.231; ...
          9, 0.229; ...
         16, 0.220; ...
         17, 0.219; ...
         32, 0.213; ...
         33, 0.213; ...
         64, 0.210; ...
         65, 0.210];

switch innerProd,
   case {'ip_tpf', 'ip_quasitpf'},
      wellConst = 0.14;
   case {'ip_rt', 'ip_simple', 'ip_quasirt'},
      ratio = max(round(d1./d2), round(d2./d1));
      wellConst = interp1(table(:,1), table(:,2), ratio, ...
                          'linear', 'extrap');
   otherwise,
      error(id('InnerProduct:Unknown'), ...
            'Unknown inner product ''%s''.', innerProd);
end

%--------------------------------------------------------------------------

function Z = getDepth(G, cells)
direction = gravity();
dims      = G.griddim;
if norm(direction(1:dims)) > 0,
   direction = direction ./ norm(direction(1:dims));
else
   direction      = zeros(1, dims);
   direction(end) = 1;
end
Z = G.cells.centroids(cells, :) * direction(1:dims).';

%--------------------------------------------------------------------------

function [dx, dy, dz] = cellDimsCG(G,ix)
% cellDims -- Compute physical dimensions of all cells in single well
%
% SYNOPSIS:
%   [dx, dy, dz] = cellDims(G, ix)
%
% PARAMETERS:
%   G  - Grid data structure.
%   ix - Cells for which to compute the physical dimensions (bounding
%        boxes).
%
% RETURNS:
%   dx, dy, dz -- Size of bounding box for each cell.  In particular,
%                 [dx(k),dy(k),dz(k)] is Cartesian BB for cell ix(k).
n = numel(ix);
[dx, dy, dz] = deal(zeros([n, 1]));
ixc = G.cells.facePos;

for k = 1 : n,
    c = ix(k);                                     % Current cell
    f = G.cells.faces(ixc(c) : ixc(c + 1) - 1, 1); % Faces on cell
    assert(numel(f)==6);
    [~, ff] = sortrows(abs(G.faces.normals(f,:)));
    f = f(ff(end:-1:1));
    dx(k) = 2*G.cells.volumes(c) / (sum(G.faces.areas(f(1:2))));
    dy(k) = 2*G.cells.volumes(c) / (sum(G.faces.areas(f(3:4))));
    dz(k) = 2*G.cells.volumes(c) / (sum(G.faces.areas(f(5:6))));
end



function [dx, dy, dz] = cellDims(G, ix)
% cellDims -- Compute physical dimensions of all cells in single well
%
% SYNOPSIS:
%   [dx, dy, dz] = cellDims(G, ix)
%
% PARAMETERS:
%   G  - Grid data structure.
%   ix - Cells for which to compute the physical dimensions
%
% RETURNS:
%   dx, dy, dz -- [dx(k) dy(k)] is bounding box in xy-plane, while dz(k) =
%                 V(k)/dx(k)*dy(k)

n = numel(ix);
[dx, dy, dz] = deal(zeros([n, 1]));

ixc = G.cells.facePos;
ixf = G.faces.nodePos;

for k = 1 : n,
   c = ix(k);                                     % Current cell
   f = G.cells.faces(ixc(c) : ixc(c + 1) - 1, 1); % Faces on cell
   e = mcolon(ixf(f), ixf(f + 1) - 1);            % Edges on cell

   nodes  = unique(G.faces.nodes(e, 1));          % Unique nodes...
   coords = G.nodes.coords(nodes,:);            % ... and coordinates

   % Compute bounding box
   m = min(coords);
   M = max(coords);

   % Size of bounding box
   dx(k) = M(1) - m(1);
   if size(G.nodes.coords, 2) > 1,
      dy(k) = M(2) - m(2);
   else
      dy(k) = 1;
   end

   if size(G.nodes.coords, 2) > 2,
      dz(k) = G.cells.volumes(ix(k))/(dx(k)*dy(k));
   else
      dz(k) = 1;
   end
end

%--------------------------------------------------------------------------

function p = permDiag3D(rock, inx)
if isempty(rock),
   error(id('Rock:Empty'), ...
         'Empty input argument ''rock'' is not supported');
elseif ~isfield(rock, 'perm'),
   error(id('Rock:NoPerm'), ...
         '''rock'' must include permeability data');
elseif size(rock.perm, 2) == 1,
   p = rock.perm(inx, [1, 1, 1]);
elseif size(rock.perm, 2) == 3,
   p = rock.perm(inx, :);
else
   p = rock.perm(inx, [1, 4, 6]);
end

%--------------------------------------------------------------------------

function p = permDiag2D(rock, inx)
if isempty(rock),
   error(id('Rock:Empty'), ...
         'Empty input argument ''rock'' is not supported');
elseif ~isfield(rock, 'perm'),
   error(id('Rock:NoPerm'), ...
         '''rock'' must include permeability data');
elseif size(rock.perm, 2) == 1,
   p = rock.perm(inx, [1, 1]);
elseif size(rock.perm, 2) == 2,
   p = rock.perm(inx, :);
else
   p = rock.perm(inx, [1, 3]);
end

%--------------------------------------------------------------------------

function s = id(s)
s = ['addWell:', s];

%--------------------------------------------------------------------------
% A funciton to compute the representative radius of the grid block in
% which the well is completed.
% rR = sqrt(re * rw).
% Here, rw is the wellbore radius, re is the area equivalent radius of the
% grid block where the well is completed, which means the circle with radius
% re has the same area as the cross section of the grid block in the
% completion's orthogonal direction.
% The current formulation theoretically only works for Cartisian grids,
% while it has been working well for the cases we have,
% including some corner-point grids.
% TODO: REMAIN TO BE VERIFIED for really twisted grids.
function rr = radiusRep(G, radius, welldir, cells)

if(isfield(G,'nodes'))
   [dx, dy, dz] = cellDims(G, cells);
else
   [dx, dy, dz] = cellDimsCG(G, cells);
end

welldir = lower(welldir);
if numel(welldir) == 1
    welldir = repmat(welldir, numel(cells), 1);
end
re = zeros(size(welldir, 1), 1);

% The following formualtion only works for Cartisian mesh
ci = welldir == 'x';
re(ci) = sqrt(dy(ci) .* dz(ci) / pi);

ci = welldir == 'y';
re(ci) = sqrt(dx(ci) .* dz(ci) / pi);

ci = welldir == 'z';
re(ci) = sqrt(dy(ci) .* dx(ci) / pi);

rr = sqrt( re .* radius);


