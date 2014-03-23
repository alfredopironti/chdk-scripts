--[[
Authors: Fraser McCrossan
         Alfredo Pironti
         Torben S.

An accurate intervalometer script, with pre-focus and screen power off options.
http://chdk.wikia.com/wiki/Lua/Scripts:_Accurate_Intervalometer_with_power-saving_and_pre-focus

Tested on G9, A2000, should work on most cameras.

Requires CHDK version 1.2 (depends on set_lcd_display())

Features:
 - Takes as input frame interval plus total desired run-time (or "endless")
 - displays frame count, frame total, remaining time and free space after each frame
   (in endless mode, displays frame count and elapsed time)
 - "Display" button during frame delays toogles display on and off
 - can turn off the display after a given number of frames
 - can pre-focus before starting then go to manual focus mode
 - use SET button to exit 

 See bottom of script for main loop.
]]

--[[
@title Time-lapse
@param s Secs/frame
@default s 3
@param h Sequence hours
@default h 0
@param m Sequence minutes
@default m 0
@param e Endless?
@default e 1
@range e 0 1
@param f Fix focus at start?
@default f 0
@range f 0 1
@param d Display off frame 0=never
@default d 3
--]]

-- convert parameters into readable variable names
secs_frame, hours, minutes, endless, focus_at_start, display_off_frame = s, h, m, (e == 1), (f == 1), d

-- sanitize parameters
if secs_frame <= 0 then
	secs_frame = 1
end
if hours < 0 then
	hours = 0
end
if minutes <= 0 then
	minutes = 1
end
if display_off_frame < 0 then
	display_off_frame = 0
end


-- display status handling
-- 0 turn off
-- 1 turn on

auto_display_off = (display_off_frame > 0) -- set to false as soon as the display status is altered
display_status = 1

function display_on ()
   set_lcd_display(1)
   display_status = 1
   auto_display_off = false
end

function display_off ()
   set_lcd_display(0)
   display_status = 0
   auto_display_off = false
end

function display_toggle()
   if display_status == 1 then
      display_off()
   else
      display_on()
   end
end

-- derive actual running parameters from the more human-friendly input
-- parameters
function calculate_parameters (seconds_per_frame, hours, minutes)
   local ticks_per_frame = 1000 * secs_frame -- ticks per frame
   local total_frames = (((hours * 3600 + minutes * 60) - 1) / secs_frame) + 1 -- total frames
   return ticks_per_frame, total_frames
end

function print_status (frame, total_frames, ticks_per_frame, endless, free)
   if endless then
      local h, m, s = ticks_to_hms(frame * ticks_per_frame)
      print("#" .. frame .. ", " .. h .. "h " .. m .. "m " .. s .. "s")
   else
      if frame < total_frames then
      	local h, m, s = ticks_to_hms(ticks_per_frame * (total_frames - frame))
	      print(frame .. "/" .. total_frames .. ", " .. h .. "h" .. m .. "m" .. s .. "s/" .. free .. " left")
	  else
         print(frame .. "/" .. total_frames .. ", " .. free .. " left")
	  end
   end
end

function ticks_to_hms (ticks)
   local secs = (ticks + 500) / 1000 -- round to nearest seconds
   local s = secs % 60
   secs = secs / 60
   local m = secs % 60
   local h = secs / 60
   return h, m, s
end

-- sleep, but using wait_click(); return true if a key was pressed, else false
function next_frame_sleep (frame, start_ticks, ticks_per_frame, total_frames)
   -- this calculates the number of ticks between now and the time of
   -- the next frame
	if frame == total_frames then
   	return false
   end
   local next_frame = start_ticks + frame * ticks_per_frame
   local sleep_time = next_frame - get_tick_count()
   if sleep_time < 1 then
      sleep_time = 1
   end
   wait_click(sleep_time)
   return not is_key("no_key")
end

-- delay for the appropriate amount of time, but respond to
-- the display key (allows turning off display to save power)
-- return true if we should exit, else false
function frame_delay (frame, start_ticks, ticks_per_frame, total_frames)
   -- this returns true while a key has been pressed, and false if
   -- none
   while next_frame_sleep (frame, start_ticks, ticks_per_frame, total_frames) do
      -- honour the display button
      if is_key("display") then
   		display_toggle()
      end
      -- if set key is pressed, indicate that we should stop
      if is_key("set") then
      	return true
      end
   end
   return false
end

-- wait for "name" button click until timeout.
-- returns true if button was clicked, false if timeout expired
function wait_button(timeout, name)
	if timeout < 1 then
		return false
	end
	local cur_timeout = timeout
	local start_time = get_tick_count()
	while cur_timeout > 0 do
		wait_click(cur_timeout)
		if is_key("no_key") then
			-- timeout expired
			return false
		else
			if is_key(name) then
				-- user clicked requested key
				return true
			end
		end
		-- user clicked an unwanted key, we continue sleeping
		local now = get_tick_count()
		local elapsed = now - start_time
		start_time = now
		cur_timeout = cur_timeout - elapsed
	end
	return false
end

-- switch to autofocus mode, pre-focus, then go to manual focus mode
function pre_focus()
   set_aflock(0)
   local try = 1
   while try <= 5 do
      print("Pre-focus attempt " .. try)
      press("shoot_half")
      sleep(2000)
      if get_focus_state() > 0 then
   		set_aflock(1)
   		return get_focus()
      end
      release("shoot_half")
      sleep(500)
      try = try + 1
   end
   return -1
end

if focus_at_start then
	local got_focus = pre_focus()
   if got_focus < 0 then
      print "Unable to reach pre-focus"
      print("Starting to shoot in 1 second")
      sleep(1000)
   else
      local refocus = true
      while refocus do
         print("Press SET to focus again")
         print("or shooting will start in 1 second")
         refocus = wait_button(1000,"set")
         release("shoot_half")
         if refocus then
            got_focus = pre_focus()
            if got_focus < 0 then
               refocus = false
               print "Unable to reach pre-focus"
               print("Starting to shoot in 1 second")
               sleep(1000)
            end
         end
      end
   end
else
	print("Starting to shoot in 1 second")
	sleep(1000)
end

ticks_per_frame, total_frames = calculate_parameters(secs_frame, hours, minutes)

frame = 1

print "Press SET to exit"

start_ticks = get_tick_count()

while endless or frame <= total_frames do
   local free = get_jpg_count() - 1 -- to account for the one we're going to make
   if free < 0 then
   	print "Memory full"
   	break
   end
   print_status(frame, total_frames, ticks_per_frame, endless, free)
   if auto_display_off and frame > display_off_frame then
      display_off()
   end
   shoot()
   if frame_delay(frame, start_ticks, ticks_per_frame, total_frames) then
      print "User quit"
      break
   end
   frame = frame + 1
end

set_aflock(0)
display_on()