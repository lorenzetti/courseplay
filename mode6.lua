function courseplay:handle_mode6(self, allowedToDrive, workSpeed, fill_level, lx , lz )
	local workTool --= self.tippers[1] -- to do, quick, dirty and unsafe
	local activeTipper = nil
	local specialTool = false

	--[[
	if self.attachedCutters ~= nil then
		for cutter, implement in pairs(self.attachedCutters) do
			AICombine.addCutterTrigger(self, cutter);
		end;
	end;
	--]]

	local workArea = (self.recordnumber > self.cp.startWork) and (self.recordnumber < self.cp.finishWork)
	local isFinishingWork = false
	local hasFinishedWork = false
	if self.recordnumber == self.cp.finishWork and self.cp.abortWork == nil then
		local _,y,_ = getWorldTranslation(self.cp.DirectionNode)
		local _,_,z = worldToLocal(self.cp.DirectionNode,self.Waypoints[self.cp.finishWork].cx,y,self.Waypoints[self.cp.finishWork].cz)
		z = -z
		local frontMarker = Utils.getNoNil(self.cp.aiFrontMarker,-3)
		if frontMarker + z < 0 then
			workArea = true
			isFinishingWork = true
		elseif self.cp.finishWork ~= self.cp.stopWork then
				self.recordnumber = math.min(self.cp.finishWork+1,self.maxnumber)
		end		
	end	
	if workArea then
		workSpeed = 1;
	end
	if (self.recordnumber == self.cp.stopWork or self.cp.last_recordnumber == self.cp.stopWork) and self.cp.abortWork == nil and not self.cp.isLoaded and not isFinishingWork then
		allowedToDrive = false
		courseplay:setGlobalInfoText(self, 'WORK_END');
		hasFinishedWork = true
	end

	for i=1, #(self.tippers) do
		workTool = self.tippers[i];
		local tool = self
		if courseplay:isAttachedCombine(workTool) then
			tool = workTool
		end

		local isFolding, isFolded, isUnfolded = courseplay:isFolding(workTool);

		-- stop while folding
		if isFolding and self.cp.turnStage == 0 then
			allowedToDrive = courseplay:brakeToStop(self);
			--courseplay:debug(tostring(workTool.name) .. ": isFolding -> allowedToDrive == false", 12);
		end;

		-- implements, no combine or chopper
		if workTool ~= nil and tool.grainTankCapacity == nil then
			-- balers
			if courseplay:isBaler(workTool) then
				if self.recordnumber >= self.cp.startWork + 1 and self.recordnumber < self.cp.stopWork and self.cp.turnStage == 0 then
																			--  self, workTool, unfold, lower, turnOn, allowedToDrive, cover, unload, ridgeMarker)
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self, workTool, true,   true,  true,   allowedToDrive, nil,   nil);
					if not specialTool then
						-- automatic opening for balers
						if workTool.balerUnloadingState ~= nil then
							fill_level = courseplay:round(fill_level, 3);
							local capacity = courseplay:round(100 * (workTool.realBalerOverFillingRatio or 1), 3);

							if courseplay:isRoundbaler(workTool) and fill_level > capacity * 0.9 and fill_level < capacity and workTool.balerUnloadingState == Baler.UNLOADING_CLOSED then
								if not workTool.isTurnedOn then
									workTool:setIsTurnedOn(true, false);
								end;
								workSpeed = 0.5;
							elseif fill_level >= capacity and workTool.balerUnloadingState == Baler.UNLOADING_CLOSED then
								allowedToDrive = false;
								if #(workTool.bales) > 0 then
									workTool:setIsUnloadingBale(true, false)
								end
							elseif workTool.balerUnloadingState ~= Baler.UNLOADING_CLOSED then
								allowedToDrive = false
								if workTool.balerUnloadingState == Baler.UNLOADING_OPEN then
									workTool:setIsUnloadingBale(false)
								end
							elseif fill_level >= 0 and not workTool.isTurnedOn and workTool.balerUnloadingState == Baler.UNLOADING_CLOSED then
								workTool:setIsTurnedOn(true, false);
							end
						end
					end
				end

				if self.cp.last_recordnumber == self.cp.stopWork -1 and workTool.isTurnedOn then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,false,false,false,allowedToDrive,nil,nil)
					if not specialTool and workTool.balerUnloadingState == Baler.UNLOADING_CLOSED then
						workTool:setIsTurnedOn(false, false);
					end
				end

			-- baleloader, copied original code parts
			elseif courseplay:is_baleLoader(workTool) or courseplay:isSpecialBaleLoader(workTool) then
				if workArea and fill_level ~= 100 then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,true,true,true,allowedToDrive,nil,nil);
					if not specialTool then
						-- automatic stop for baleloader
						if workTool.grabberIsMoving or workTool:getIsAnimationPlaying("rotatePlatform") then
							allowedToDrive = false
						end
						if not workTool.isInWorkPosition and fill_level ~= 100 then
							--g_client:getServerConnection():sendEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_BUTTON_WORK_TRANSPORT));
							workTool.grabberIsMoving = true
							workTool.isInWorkPosition = true
							BaleLoader.moveToWorkPosition(workTool)
						end
					end;
				end

				if (fill_level == 100 and self.cp.hasUnloadingRefillingCourse or self.recordnumber == self.cp.stopWork) and workTool.isInWorkPosition and not workTool:getIsAnimationPlaying("rotatePlatform") then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,false,false,false,allowedToDrive,nil,nil);
					if not specialTool then
						workTool.grabberIsMoving = true
						workTool.isInWorkPosition = false
						-- move to transport position
						BaleLoader.moveToTransportPosition(workTool)
					end;
				end

				if fill_level == 100 and not self.cp.hasUnloadingRefillingCourse then
					if self.cp.automaticUnloadingOnField then
						self.cp.unloadOrder = true
						courseplay:setGlobalInfoText(self, 'UNLOADING_BALE');
					else
						specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,false,false,false,allowedToDrive,nil,nil); --TODO: unclear
					end
				end

				-- automatic unload
				if (not workArea and self.Waypoints[self.cp.last_recordnumber].wait and (self.wait or fill_level == 0)) or self.cp.unloadOrder then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,false,false,false,allowedToDrive,nil,true);
					if not specialTool then
						if workTool.emptyState ~= BaleLoader.EMPTY_NONE then
							if workTool.emptyState == BaleLoader.EMPTY_WAIT_TO_DROP then
								-- BaleLoader.CHANGE_DROP_BALES
								g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_DROP_BALES), true, nil, workTool)
							elseif workTool.emptyState == BaleLoader.EMPTY_WAIT_TO_SINK then
								-- BaleLoader.CHANGE_SINK
								g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_SINK), true, nil, workTool)
							elseif workTool.emptyState == BaleLoader.EMPTY_WAIT_TO_REDO then
								-- BaleLoader.CHANGE_EMPTY_REDO
								g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_EMPTY_REDO), true, nil, workTool);
							end
						else
							--BaleLoader.CHANGE_EMPTY_START
							if BaleLoader.getAllowsStartUnloading(workTool) then
								g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_EMPTY_START), true, nil, workTool)
							end
							self.cp.unloadOrder = false
						end
					end;
				end;
			--END baleloader


			-- other worktools, tippers, e.g. forage wagon
			else
				if workArea and fill_level ~= 100 and ((self.cp.abortWork == nil) or (self.cp.abortWork ~= nil and self.cp.last_recordnumber == self.cp.abortWork) or (self.cp.runOnceStartCourse)) and self.cp.turnStage == 0  then
								--courseplay:handleSpecialTools(self,workTool,unfold,lower,turnOn,allowedToDrive,cover,unload)
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,true,true,true,allowedToDrive,nil,nil)
					if allowedToDrive then
						if not specialTool then
							--unfold
							local recordnumber = math.min(self.recordnumber+2 ,self.maxnumber)
							local forecast = Utils.getNoNil(self.Waypoints[recordnumber].ridgeMarker,0)
							local marker = Utils.getNoNil(self.Waypoints[self.recordnumber].ridgeMarker,0)
							local waypoint = math.max(marker,forecast)
							if courseplay:isFoldable(workTool) and not isFolding and not isUnfolded then
								if not workTool.cp.hasSpecializationPlough then
									courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
									workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
									self.cp.runOnceStartCourse = false;
								elseif waypoint == 2 and self.cp.runOnceStartCourse then --wegpunkte finden und richtung setzen...
									courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
									workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
									if workTool:getIsPloughRotationAllowed() then
										AITractor.aiRotateLeft(self);
										self.cp.runOnceStartCourse = false;
									end
								elseif self.cp.runOnceStartCourse then
									courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
									workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
									self.cp.runOnceStartCourse = false;
								end
							end;


							if not isFolding and isUnfolded and not waitForSpecialTool then --TODO: where does "waitForSpecialTool" come from? what does it do?
								--lower
								if workTool.needsLowering and workTool.aiNeedsLowering then
									self:setAIImplementsMoveDown(true);
									courseplay:debug(string.format('%s: lower order', nameNum(workTool)), 17);
								end;

								--turn on
								if workTool.setIsTurnedOn ~= nil and not workTool.isTurnedOn then
									workTool:setIsTurnedOn(true, false);
									courseplay:debug(string.format('%s: turn on order', nameNum(workTool)), 17);
									self.cp.runOnceStartCourse = false
									courseplay:setMarkers(self, workTool);
								end;

								if workTool.setIsPickupDown ~= nil and workTool.pickup then
									if workTool.pickup.isDown == nil or (workTool.pickup.isDown ~= nil and not workTool.pickup.isDown) then
										workTool:setIsPickupDown(true, false);
										courseplay:debug(string.format('%s: lower pickup order', nameNum(workTool)), 17);
									end;
								end;
							end;
						end;
					end
				elseif not workArea or self.cp.abortWork ~= nil or self.cp.isLoaded or self.cp.last_recordnumber == self.cp.stopWork then
					workSpeed = 0;
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,false,false,false,allowedToDrive,nil,nil)
					if not specialTool then
						if not isFolding then
							--turn off
							if workTool.setIsTurnedOn ~= nil and workTool.isTurnedOn then
								workTool:setIsTurnedOn(false, false);
								courseplay:debug(string.format('%s: turn off order', nameNum(workTool)), 17);
							end;
							if workTool.setIsPickupDown ~= nil and workTool.pickup then
								if workTool.pickup.isDown == nil or (workTool.pickup.isDown ~= nil and workTool.pickup.isDown) then
									workTool:setIsPickupDown(false, false);
									courseplay:debug(string.format('%s: raise pickup order', nameNum(workTool)), 17);
								end;
							end;

							--raise
							if workTool.needsLowering and workTool.aiNeedsLowering and self.cp.turnStage == 0 then
								self:setAIImplementsMoveDown(false);
								courseplay:debug(string.format('%s: raise order', nameNum(workTool)), 17);
							end;
						end;

						--fold
						if courseplay:isFoldable(workTool) and not isFolding and not isFolded then
							courseplay:debug(string.format('%s: fold order (foldDir=%d)', nameNum(workTool), -workTool.cp.realUnfoldDirection), 17);
							workTool:setFoldDirection(-workTool.cp.realUnfoldDirection);
							--workTool:setFoldDirection(-workTool.turnOnFoldDirection);
						end;
					end;
				end;

				-- done tipping
				local tipper_fill_level, tipper_capacity = self:getAttachedTrailersFillLevelAndCapacity()

				if tipper_fill_level ~= nil and tipper_capacity ~= nil then
					if self.cp.unloadingTipper ~= nil and self.cp.unloadingTipper.fillLevel == 0 then
						self.cp.unloadingTipper = nil

						if tipper_fill_level == 0 then
							self.cp.isUnloaded = true
							self.cp.currentTipTrigger = nil
						end
					end

					-- damn, i missed the trigger!
					if self.cp.currentTipTrigger ~= nil then
						local trigger = self.cp.currentTipTrigger
						local triggerId = trigger.triggerId
						if trigger.isPlaceableHeapTrigger then
							triggerId = trigger.rootNode;
						end;

						if trigger.specialTriggerId ~= nil then
							triggerId = trigger.specialTriggerId
						end
						local trigger_x, trigger_y, trigger_z = getWorldTranslation(triggerId);
						local ctx, cty, ctz = getWorldTranslation(self.rootNode);
						if courseplay:distance(ctx, ctz, trigger_x, trigger_z) > 60 then
							self.cp.currentTipTrigger = nil
						end
					end

					-- tipper is not empty and tractor reaches TipTrigger
					if tipper_fill_level > 0 and self.cp.currentTipTrigger ~= nil and self.recordnumber > 3 then
						allowedToDrive, activeTipper = courseplay:unload_tippers(self)
						self.cp.infoText = courseplay:loc("CPTriggerReached") -- "Abladestelle erreicht"
					end
				end;
			end; --END other tools

			-- Begin Work   or goto abortWork
			if self.cp.last_recordnumber == self.cp.startWork and fill_level ~= 100 then
				if self.cp.abortWork ~= nil then
					if self.cp.abortWork < 5 then
						self.cp.abortWork = 6
					end
					self.recordnumber = self.cp.abortWork
					if self.recordnumber < 2 then
						self.recordnumber = 2
					end
					if self.Waypoints[self.recordnumber].turn ~= nil or self.Waypoints[self.recordnumber+1].turn ~= nil  then
						self.recordnumber = self.recordnumber -2
					end
				end
			end
			-- last point reached restart
			if self.cp.abortWork ~= nil then
				if (self.cp.last_recordnumber == self.cp.abortWork ) and fill_level ~= 100 then
					self.recordnumber = self.cp.abortWork + 2  -- drive to waypoint after next waypoint
					self.cp.abortWork = nil
				end
			end
			-- safe last point
			if (fill_level == 100 or self.cp.isLoaded) and workArea and not courseplay:isBaler(workTool) then
				if self.cp.hasUnloadingRefillingCourse and self.cp.abortWork == nil then
					self.cp.abortWork = self.cp.last_recordnumber - 10
					self.recordnumber = self.cp.stopWork - 4
					if self.recordnumber < 1 then
						self.recordnumber = 1
					end
					--courseplay:debug(string.format("Abort: %d StopWork: %d",self.cp.abortWork,self.cp.stopWork), 12)
				elseif not self.cp.hasUnloadingRefillingCourse and not self.cp.automaticUnloadingOnField then
					allowedToDrive = false;
					courseplay:setGlobalInfoText(self, 'NEEDS_UNLOADING');
				elseif not self.cp.hasUnloadingRefillingCourse and self.cp.automaticUnloadingOnField then
					allowedToDrive = false;
				end;
			end;

		else  --COMBINES

			--Start combine
			local pipeState = 0;
			if tool.getCombineTrailerInRangePipeState ~= nil then
				pipeState = tool:getCombineTrailerInRangePipeState();
			end;
			if workArea and not tool.isAIThreshing and self.cp.abortWork == nil and self.cp.turnStage == 0 then
				specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,true,true,true,allowedToDrive,nil,nil)
				if not specialTool then
					local weatherStop = not tool:getIsThreshingAllowed(true)
					if tool.grainTankCapacity == 0 then
						if courseplay:isFoldable(workTool) and not tool.isThreshing and not isFolding and not isUnfolded then
							courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
							workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
						end;
						if not isFolding and not tool.isThreshing then
							tool:setIsThreshing(true);
							if pipeState > 0 then
								tool:setPipeState(pipeState);
							else
								tool:setPipeState(2);
							end;
						end
						if pipeState == 0 and self.cp.turnStage == 0 then
							tool.cp.waitingForTrailerToUnload = true
						end
					else
						local fillLevelPct = tool.grainTankFillLevel * 100 / tool.grainTankCapacity;

						if courseplay:isFoldable(workTool) and not tool.isThreshing and not isFolding and not isUnfolded then
							courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
							workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
						end;
						if not isFolding and fillLevelPct < 100 and not tool.waitingForDischarge and not tool.isThreshing and not weatherStop then
							tool:setIsThreshing(true);
						end

						if fillLevelPct >= 100 or tool.waitingForDischarge or (tool.cp.stopWhenUnloading and tool.pipeIsUnloading and tool.courseplayers[1] ~= nil) then
							tool.waitingForDischarge = true
							allowedToDrive = false;
							tool:setIsThreshing(false);
							if fillLevelPct < 80 and (not tool.cp.stopWhenUnloading or (tool.cp.stopWhenUnloading and tool.courseplayers[1] == nil)) then
								tool.waitingForDischarge = false
								-- print(string.format('fillLevelPct=%.1f, stopWhenUnloading=%s, pipeIsUnloading=%s, tool.courseplayers[1]=%s -> set waitingForDischarge to false', fillLevelPct, tostring(tool.cp.stopWhenUnloading), tostring(tool.pipeIsUnloading), tostring(tool.courseplayers[1])));
							end
						end

						if weatherStop then
							allowedToDrive = false;
							tool:setIsThreshing(false);
							courseplay:setGlobalInfoText(self, 'WEATHER');
						end

					end
				end
			 --Stop combine
			elseif self.recordnumber == self.cp.stopWork or self.cp.abortWork ~= nil then
				local isEmpty = tool.grainTankFillLevel == 0
				if self.cp.abortWork == nil then
					allowedToDrive = false;
				end
				if isEmpty then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,false,false,false,allowedToDrive,nil)
				else
					specialTool, allowedToDrive = courseplay:handleSpecialTools(self,workTool,true,false,false,allowedToDrive,nil)
				end
				if not specialTool then
					tool:setIsThreshing(false);
					if courseplay:isFoldable(workTool) and isEmpty and not isFolding and not isFolded then
						courseplay:debug(string.format('%s: fold order (foldDir=%d)', nameNum(workTool), -workTool.cp.realUnfoldDirection), 17);
						workTool:setFoldDirection(-workTool.cp.realUnfoldDirection);
					end;
					tool:setPipeState(1)
				end
			end

			if tool.cp.isCombine and tool.isThreshing and tool.grainTankFillLevel >= tool.grainTankCapacity*0.8  or ((pipeState > 0 or courseplay:isAttachedCombine(workTool))and not courseplay:isSpecialChopper(workTool))then
				tool:setPipeState(2)
			elseif  pipeState == 0 and tool.cp.isCombine and tool.grainTankFillLevel < tool.grainTankCapacity then
				tool:setPipeState(1)
			end
			if tool.cp.waitingForTrailerToUnload then
				allowedToDrive = false;
				if tool.cp.isCombine or courseplay:isAttachedCombine(workTool) then
					if tool.isCheckedIn == nil or (pipeState == 0 and tool.grainTankFillLevel == 0) then
						tool.cp.waitingForTrailerToUnload = false
					end
				elseif tool.cp.isChopper then
					if (tool.pipeParticleSystems[9].isEmitting or pipeState > 0) then
						self.cp.waitingForTrailerToUnload = false
					end
				end
			end

			local dx,_,dz = localDirectionToWorld(self.cp.DirectionNode, 0, 0, 1);
			local length = Utils.vector2Length(dx,dz);
			if self.cp.turnStage == 0 then
				self.aiThreshingDirectionX = dx/length;
				self.aiThreshingDirectionZ = dz/length;
			else
				self.aiThreshingDirectionX = -(dx/length);
				self.aiThreshingDirectionZ = -(dz/length);
			end

		end
	end; --END for i in self.tippers

	if hasFinishedWork then
		isFinishingWork = true
	end
	return allowedToDrive, workArea, workSpeed, activeTipper ,isFinishingWork
end