function [ X_eroded,Y_eroded,durability ] = erode_polygon( x,y,dl,n_pixels,mean_durability,pe,r,corr,seuil_area,contact_points,aa,bb,seuil_contact,reordering_method)
% ERODE_POLYGON function that erodes a polygon. 
% The algorithm discretize the polygon into pixels and each pixel is then 
% eroded iteratively, according to it's resistance and the volume of air 
% surronding it.
%
% %%%%%% usage %%%%%%
%
% %% INPUTS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  - x        : x coordinates of the vertices of the poylgon
%  - y        : y coordinates of the vertices of the polygon
%  - dl       : aimed erosion on straight lines
%  - n_pixels : number of pixels used for discretization along the biggest
%               dimension.
%  - mean_durability : The mean aimed durability (! Should not be below
%               0.02, if not the algorithm does not give good results.
%  - pe       : the volumetric part of the equation is risen to the power
%               pe (the more elevated, the more roundness will appear, if 0
%               the edges will stay straight)
%  - dx       : the size of the pixels along x axis
%  - r        : the radius of the bubble
%  - seuil_area : if the ratio between the area of the eroded polygon and
%               the area of the original polygon goes under this value,
%               erosion will stop. 
%  - contact_points : Px3 matrix containing the coordinates of the contact
%               points in the two first columns, and the lengths of
%               the edges concerned in the third column.
%  - a        : length of the zone where the damping function is 0
%               around the contact point.
%  - b        : length of the zone till which the damping function
%               grows linearly till 1.
%  - seuil_contact: limit on the edge length, if the edge is <
%               seuil_contact, there is no contact point on this edge.
%  - reordering_method : 'angular' for angular reordering and
%               'nearest_neighbor' for nearest_neighbor reordering of the nodes after
%               the erosion process
%  - corr.    : struct containing info concerning the random field used to
%               generate the durability function.
%        name : 'gauss' for gaussian, 'exp' for exponential or 'turb' for
%               turbulent
%        c0   : The scaling parameters for the correlation function. c0 may
%               be a scalar for isotropic correlation or a vector for
%               anisotropic correlation. In the anisotropic case, the
%               vector must have d elements, where d is the dimesion of a
%               mesh point.
%        c1   : The second scaling parameters for the 'turbulent'
%               correlation function. Not used with 'gauss' or 'exp'.
%
%        sigma: The variance scaling parameter. May be a scalar or a vector
%               the size of the mesh.
%
%        C     :The correlation matrix between the unknown elements of the
%               field. If the precomputed correlation matrix fits into
%               memory, this is the best option.
%
%        A     :The correlation matrix between data points.
%
%        B     :The correlation matrix between data points and unknowns.
%               The code expects this to be structured so that rows
%               correspond to mesh points and columns correspond to data
%               points.
%
% %% OUTPUTS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  - X_eroded : x coordinates of vertices of the eroded polygon
%  - Y_eroded : y coordinates of vertices of the eroded polygon
%  - durability : The map of the durability of the polygon.
%
% %% AUTEUR : Martin HOFMANN
% %% DATE   : November 2015
% See also ERODE_STONES
% Modified Shengahn ZHANG 06.11.2018 
% TO DO: 
% Delete the 100 both from the initial value and also from the calculation
% of iteration steps. 
% Note that in this file, the state variable is set to 100, which is the
% reason why in the calculation of iteration steps, there is a 100 in the
% beginning of the expression. However, this is not necessary, for the same
% value of 100 appears at both sides of the equation. 
%
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% INITIALIZATIONS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Meshing of the square containing the stone
delta_x=max(x)-min(x); %x width
delta_y=max(y)-min(y); %y height

% We fix the number of pixels along the biggest dimension to n_pixels

dx=max(delta_x/n_pixels,delta_y/n_pixels);

my=round(delta_y/dx); % number of pixel along x coordinate
nx=round(delta_x/dx); % number of pixels along y coordinate

i_x=min(x); % coordinate of the left border
i_y=min(y); % coordinate of the bottom border
x=x-i_x; % put the origin at the bottom left corner
y=y-i_y;

x=x./dx; %
y=y./dx;
b=ceil(r/dx)+1;
mask=poly2mask(x,y,my,nx); % Polymask is a matlab function that creates a mask of the polygon in a matrix (see help polymask)

A=sum(sum(mask))*dx^2; % Computation of stone area
An=A;

% We widen the mask to be able to compute the bubbles around the whole
% polygon
mask=[zeros(b,nx);mask;zeros(b,nx)];
mask=[zeros(my+2*b,b),mask,zeros(my+2*b,b)];
[rnz,cnz]=find(mask); % non-zero elements of the mask (stone)
surf_v=[];

state =mask*100; % Initialization of state matrix

mask_exposure=get_mask_exposure(dx,r); % Computation of the mask of the bubble
bulle=sum(sum(mask_exposure)); % Volume of the bubble
n=(size(mask_exposure,1)-1)/2; % the bubble is inscribed in a 2n+1 square
v_air_h=sum(sum(mask_exposure(1:n,:))); % volume of air if the bubble is centered on a pixel on a straight line
ratio=v_air_h/bulle; % Ratio between air and stone on straight lines
it=100*dl*mean_durability/(ratio^pe*dx); % The number of iterations needed is computed given the durability and the target erosion on straight lines

io=size(mask,1)/2;
jo=size(mask,2)/2;

% Computation of durability matrix
durability=-1*ones(nx+2*b,my+2*b);

while min(min(durability))<0
    
    [durability]=create_random_field(nx+2*b,my+2*b,corr,mean_durability);
    
end


% Computation of initial values (exposure, angle, damping)

exposure=[];
vec_angles=[];
damping_values=[];

for i=1:size(rnz)
    
    if is_on_surface(mask,rnz(i),cnz(i))
        
        surf_v=[surf_v;rnz(i),cnz(i)];
        sub_mask=~mask(rnz(i)-n:rnz(i)+n,cnz(i)-n:cnz(i)+n);
        va=sum(sum(sub_mask.*mask_exposure));
        exposure=[exposure,va/bulle];
        vec_angles=[vec_angles;atan2(cnz(i)-jo,rnz(i)-io)];
        x=(cnz(i)-b-0.5)*dx+i_x;
        y=(rnz(i)-b-0.5)*dx+i_y;
        
        if isempty(contact_points)==0

            damping_values=[damping_values,get_damping_erosion(x,y,contact_points,aa,bb,seuil_contact)];
        
        else
            
            damping_values=[damping_values,1];
            
        end
        
    end
    
end
create_video = false;
if(create_video)
    fig1 = figure;
    axis equal
    v = VideoWriter('erode_stone.avi');
    v.Quality = 100;
    v.FrameRate = 5;
    open(v)
end
%% EROSION PROCESS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

for i=1:it % Temporal iteration
    
    to_del=[]; % initialization of to add and to delete pixels
    to_add=[];
    
    for j=1:size(surf_v,1) % We iterate on surface pixels
        
        ind_i=surf_v(j,1);
        ind_j=surf_v(j,2);
        state(ind_i,ind_j)=state(ind_i,ind_j)-damping_values(j)*exposure(j)^pe/durability(ind_i,ind_j); % We compute the new state
        
        if state(ind_i,ind_j)<0 % If the state is less than 0
            
            mask(ind_i,ind_j)=0; % This coordinate of the mask becomes 0
            to_del=[to_del;j]; % This pixel is to be deleted
            to_add=[to_add;actualize_surf(mask,ind_i,ind_j)]; % Some pixels might have to be added
            exposure=update_exposure(exposure,ind_i,ind_j,surf_v,bulle,r,dx); % Exposure must be updated
            An=An-dx^2; % Area is updated
            
        end
        
    end
     
    % The corresponding values in surf_v, exposure, damping_values and
    % vec_angles are deleted.
    surf_v(to_del,:)=[];
    exposure(to_del)=[];
    damping_values(to_del)=[];
    vec_angles(to_del)=[];
    
    % If there is pixels to add
    if isempty(to_add)==0
        
        surf_v=[surf_v;to_add]; % We add them in the surf_v vector
        vec_angles=[vec_angles;atan2(to_add(:,2)-jo,to_add(:,1)-io)]; % we add them in the vec_angles vector
        exposure=add_new_exposure(exposure,to_add,mask,mask_exposure,n,bulle); % The exposure is computated and added
        if isempty(contact_points)==0 % We compute the damping values if the contact_points list is not empty
            
            for k=1:size(to_add,1)
                
                x=(to_add(k,2)-b-0.5)*dx+i_x; % X coordinate
                y=(to_add(k,1)-b-0.5)*dx+i_y; % Y coordinate
                damping_values=[damping_values,get_damping_erosion(x,y,contact_points,aa,bb,seuil_contact)]; % Updating damping values
            
            end
            
        else
            
            damping_values=[damping_values,ones(1,size(to_add,1))]; % If there is no contact point, damping is 1.
        
        end
        
        [surf_v,ind_rm] = unique(surf_v, 'rows') ; % We reorganize the surf_v vector
        exposure=exposure(ind_rm); % Same ordering on exposure
        damping_values=damping_values(ind_rm); % Same ordering on damping_values
        vec_angles=vec_angles(ind_rm); % Same ordering on vec_angles
    
    end
    
    if An/A<seuil_area % If the area goes under a certain ratio of the initial, process of erosion is stopped
        
        break;
        
    end
    if (create_video == true && mod(i,2)==0)
    plot_pixel(fig1, surf_v,dx,i_x,i_y,reordering_method)
    figure(fig1);
    hold on
    plot(x,y,'r')
    end
end

%% POST TREATMENT %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% In this part, we recreate a polygon from the mask we have

if size(surf_v,1)~=0 % If there is still a stone
    
    X_eroded=zeros(size(surf_v,1),1); % Each surface pixel will become a vertex of the polygon
    Y_eroded=zeros(size(surf_v,1),1);
    
    for j=1:size(surf_v,1) % We recompute the x-y coordinates
        
        X_eroded(j,1)=(surf_v(j,2)-b-0.5)*dx+i_x;
        Y_eroded(j,1)=(surf_v(j,1)-b-0.5)*dx+i_y;
    
    end
    
    switch reordering_method
        
        case 'angular'
            x=mean(X_eroded); % ~center of the stone
            y=mean(Y_eroded); % ~center of the stone
            
            % We sort the remaining pixels by angle
            vecs = [X_eroded,Y_eroded]-repmat([x y],size(X_eroded,1),1);
            
            angles=zeros(size(vecs,1),1);
           
            for i=1:size(vecs,1)
             
                angles(i) = atan2(vecs(i,1),vecs(i,2));
            end
            
            [~, index]=sort(angles);
            X_eroded=X_eroded(index); % Sorting according to the angle
            Y_eroded=Y_eroded(index); % Sorting according to the angle
     
        case 'nearest_neighbor'
     
            poly=[X_eroded,Y_eroded];
            poly=reorder_by_distance_polygon(poly);
            
            X_eroded=poly(:,1);
            Y_eroded=poly(:,2);
  
    end
    
else
    
    X_eroded=[];
    Y_eroded=[];
    
end

end

% function added to check the main function, it draws a dx wide square pixel given its
% coordinate
function [h] = draw_pixel(surf_1,surf_2,dx,color,b,i_x,i_y)
X_eroded=(surf_2-b-0.5)*dx+i_x;
Y_eroded=(surf_1-b-0.5)*dx+i_y;
h=rectangle('Position',[X_eroded-dx/2,Y_eroded-dx/2,dx,dx],'FaceColor',color,'EdgeColor',[245/255 245/255 220/255],...
    'LineWidth',0.001);
end