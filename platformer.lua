pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- linear interpolation function
function lerp(v0, v1, t)
  return v0 + t * (v1 - v0)
end

function _init()
  tilesize = 8
  player = { x = 3, y = 13 }
  player.speed = { x = 0, y = 0 }
  player.collision = {
    size = {
      horizontal = {
        width = 10 / tilesize,
        height = 9 / tilesize
      },
      vertical = {
        width = 6 / tilesize,
        height = 13 / tilesize
      }
    }
  }
  player.anims = {
    standing = { 12 },
    jumping = { 14 },
    walking = { 32, 34, 36, 38, 40, 42, 44, 46 }
  }
  updatecollisionbox(player)
  screensize = {
    width = 128,
    height = 128
  }
  mapsize = {
    width = 53,
    height = 32
  }
  
  -- pixels of downward speed applied each frame
  grav = 1.0 / tilesize
  maxgrav = 7.5 / tilesize
  
  -- horizontal movement speed
  movspeed = 2.25 / tilesize
  
  -- jump speed
  jumpspeed = 10.5 / tilesize
  
  -- jump buffering
  jumpbuffer = 3 -- number of frames allowed to buffer jumps
  jumpframes = jumpbuffer + 1
  wasjumppressed = false
  
  -- jump grace period
  jumpgrace = 3 -- number of frames allowed after being on the ground to still jump
  fallingframes = jumpgrace + 1
  
  -- screen bounding box beyond which the camera will snap back to the player
  camerasnap = { left = 40, top = 16, right = screensize.width - 40, bottom = screensize.height - 48 }
  cam = { x = 0, y = 0 }
end

function _update()
  player.speed.x = 0
  jumpframes = min(jumpbuffer + 1, jumpframes + 1)
  fallingframes = min(jumpgrace + 1, fallingframes + 1)

  if btn(0) then
    player.speed.x -= movspeed
  end
  if btn(1) then
    player.speed.x += movspeed
  end
  
  if btn(4) and not wasjumppressed then
    jumpframes = 0
  end
  
  if player.onground or fallingframes <= jumpgrace then
    if jumpframes <= jumpbuffer then
      jump(player)
    end
  else
    if player.jumping and not btn(4) then
      player.jumping = false
    end
  end

  applyphysics(player)
  animate(player)
  
  wasjumppressed = btn(4)

  -- update camera position
  local screenx, screeny = player.x * tilesize - cam.x, player.y * tilesize - cam.y
  
  if screenx < camerasnap.left then
    cam.x += screenx - camerasnap.left
  elseif screenx > camerasnap.right then
    cam.x += screenx - camerasnap.right
  else
    local center = player.x * tilesize - screensize.width / 2
    cam.x += (center - cam.x) / 6
  end
  
  if screeny < camerasnap.top then
    cam.y += screeny - camerasnap.top
  elseif screeny > camerasnap.bottom then
    cam.y += screeny - camerasnap.bottom
  elseif player.onground then
    local center = player.y * tilesize - screensize.height / 2
    cam.y += (center - cam.y) / 6
  end

  local maxcamx, maxcamy = 
    max(0, mapsize.width * tilesize - screensize.width), 
    max(0, mapsize.height * tilesize - screensize.height)
    
  cam.x = mid(0, cam.x, maxcamx)
  cam.y = mid(0, cam.y, maxcamy)
end

function animate(entity)
  if not entity.onground then
    setanim(entity, "jumping")
  elseif entity.speed.x ~= 0 then
    setanim(entity, "walking")
  else  
    setanim(entity, "standing")
  end
  
  entity.animframes += 1
  entity.frame = (flr(entity.animframes / 3) % #entity.anim) + 1
  
  if entity.speed.x < 0 then
    entity.mirror = true
  elseif entity.speed.x > 0 then
    entity.mirror = false
  end
end

function setanim(entity, name)
  if entity.anim ~= entity.anims[name] then
    entity.anim = entity.anims[name]
    entity.animframes = 0
  end
end

function jump(entity)
  entity.onground = false
  entity.jumping = true
  entity.curjumpspeed = jumpspeed
  jumpframes = jumpbuffer + 1
end

function applyphysics(entity)
  local speed = entity.speed

  if entity.jumping or speed.y < 0 then
    if entity.jumping then
      entity.curjumpspeed -= jumpspeed / 10
    else
      entity.curjumpspeed = 0
    end
    
    speed.y = -entity.curjumpspeed
    
    if entity.curjumpspeed <= 0 then
      entity.jumping = false
    end
  else
    speed.y = min(maxgrav, speed.y + grav)
  end
  
  local wasonground = entity.onground -- we need to know if the entity started on the ground for slopes
  entity.onground = false
  
  -- increase precision by applying physics in smaller steps
  -- the more steps, the faster things can go without going through terrain
  local steps = 1
  local highestspeed = max(abs(speed.x), abs(speed.y))
  
  if highestspeed >= 0.25 then
    steps = ceil(highestspeed / 0.25)
  end
  
  for i = 1, steps do
    entity.x += speed.x / steps
    entity.y += speed.y / steps
    
    updatecollisionbox(entity)
    
    -- slope collisions
    for tile in gettiles(entity, "floor") do
      if tile.sprite > 0 then
        local tiletop = tile.y
      
        if tile.slope then
          local slope = tile.slope
          local xoffset = entity.x - tile.x
          
          if xoffset < 0 or xoffset > 1 then
            -- only do slopes if the entity's center x coordinate is inside the tile space
            -- otherwise ignore this tile
            tiletop = nil
          else
            local alpha
            if slope.reversed then
              alpha = 1 - xoffset
            else
              alpha = xoffset
            end
            
            local slopeheight = lerp(slope.offset, slope.offset + slope.height, alpha)
            tiletop = tile.y + 1 - slopeheight
            
            -- only snap the entity down to the slope's height if it wasn't jumping or on the ground
            if entity.y < tiletop and not wasonground and not jumping then
              tiletop = nil
            end
          end
        else
          tiletop = nil
        end
        
        if tiletop then
          speed.y = 0
          entity.y = tiletop
          entity.onground = true
          entity.jumping = false
          fallingframes = 0
        end
      end
    end
    
    updatecollisionbox(entity)
    
    -- wall collisions
    for tile in gettiles(entity, "horizontal") do
      if tile.sprite > 0 and not tile.slope then
        if entity.x < tile.x + 0.5 then
          -- push out to the left
          entity.x = tile.x - entity.collision.size.horizontal.width / 2
        else
          -- push out to the right
          entity.x = tile.x + 1 + entity.collision.size.horizontal.width / 2
        end
      end
    end
    
    updatecollisionbox(entity)
    
    -- floor collisions
    for tile in gettiles(entity, "floor") do
      if tile.sprite > 0 and not tile.slope then
        speed.y = 0
        entity.y = tile.y
        entity.onground = true
        entity.jumping = false
        fallingframes = 0
      end
    end
    
    updatecollisionbox(entity)
    
    -- ceiling collisions
    for tile in gettiles(entity, "ceiling") do
      if tile.sprite > 0 and not tile.slope then
        speed.y = 0
        entity.y = tile.y + 1 + entity.collision.size.vertical.height
        entity.jumping = false
      end
    end
  end
end

-- gets all tiles that might be intersecting entity's collision box
function gettiles(entity, boxtype)
  local box = entity.collision.box[boxtype]
  local left, top, right, bottom =
    flr(box.left), flr(box.top), flr(box.right), flr(box.bottom)
    
  local x, y = left, top
    
  -- iterator function
  return function()
    if y > bottom then
      return nil
    end
    
    local sprite = mget(x, y)
    local ret = { sprite = sprite, x = x, y = y }

    local flags = fget(sprite)

    if band(flags, 128) == 128 then
      -- this is a slope if flag 7 is set
      ret.slope = {
        reversed = band(flags, 64) == 64, -- reversed if flag 6 is set,
        height = (band(flags, 7) + 1) / tilesize, -- the first 3 bits/flags set the slope height from 1-8
        offset = band(lshr(flags, 3), 7) / tilesize -- bits/flags 4 through 6 set the offset from the bottom of the tile between 0 and 7
      }
    end

    x += 1
    if x > right then
      x = left
      y += 1
    end
    
    return ret
  end
end

function updatecollisionbox(entity)
  local size = entity.collision.size

  entity.collision.box = {
    horizontal = {
      left = entity.x - size.horizontal.width / 2,
      top = entity.y - size.vertical.height + (size.vertical.height - size.horizontal.height) / 2,
      right = entity.x + size.horizontal.width / 2,
      bottom = entity.y - (size.vertical.height - size.horizontal.height) / 2
    },
    floor = {
      left = entity.x - size.vertical.width / 2,
      top = entity.y - size.vertical.height / 2,
      right = entity.x + size.vertical.width / 2,
      bottom = entity.y
    },
    ceiling = {
      left = entity.x - size.vertical.width / 2,
      top = entity.y - size.vertical.height,
      right = entity.x + size.vertical.width / 2,
      bottom = entity.y - size.vertical.height / 2
    }
  }
end

function _draw()
  camera(cam.x, cam.y)

  pal()
  palt(0, false)
  palt(14, true)

  cls(12)
  map(0, 0, 0, 0)
  
  spr(player.anim[player.frame], player.x * tilesize - 8, player.y * tilesize - 16, 2, 2, player.mirror)
end
