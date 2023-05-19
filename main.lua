-- Services
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players: Players = game:GetService("Players")

-- Shared
local Shared: Folder = ReplicatedStorage:WaitForChild("Shared")
local TicTacToe: {} = require(Shared:WaitForChild("TicTacToe"))

-- Packages
local Packages: Folder = ReplicatedStorage:WaitForChild("Packages")
local Knit: {} = require(Packages:WaitForChild("Knit"))

--  
local MatchService: {} = Knit.CreateService {
	Name = script.Name,
	Client = {
		MatchStart = Knit.CreateSignal(),
		MatchEnd = Knit.CreateSignal(),
		CheckBoard = Knit.CreateSignal(),
		UpdateBoard = Knit.CreateSignal(),
	}
}

-- Knit Services
local DataService: {}
local LevelService: {}

-- Values 
local Matches = {} -- Stores all match data

-- Compiles Data Needed to Start a Match
function MatchService:StartMatch(Player1: Player, Player2: Player)
	-- Create Match Data Where We Can Track Match State
	local MatchData = {
		PLAYER_1 = {
			Player = Player1, 
			Symbol = TicTacToe.PLAYER_1
		}, 
		PLAYER_2 = {
			Player = Player2,
			Symbol = TicTacToe.PLAYER_2
		
		},
		CurrentTurn = "PLAYER_1",		
		ID = tick(),
		Ended = false,
		Board = table.clone(TicTacToe.BOARD_TEMPLATE)
	}
	
	-- Start Match On Client
	self.Client.MatchStart:Fire(Player1, Player2, MatchData) 
	self.Client.MatchStart:Fire(Player2, Player1, MatchData)
	
	-- Insert it to match table 
	Matches[MatchData.ID] = MatchData
end

-- Checks Board if Round Has Concluded and Updates The Board 
function MatchService:CheckBoard(Player: Player, MatchID: number, Cell: string)
	-- Get Match 
	local Match: {} = Matches[MatchID]
	local Board: {} = Match.Board
	
	-- Another Check From Server Incase The Player is an Exploiter or Somehow Got Passed From Initial Check on Client
	-- Check If Cell Selected Is Occupied 
	-- Checks If Its Actually The Player's Turn 
	if TicTacToe.CheckIfCellOccupied(Board, Cell) then return end
	if not (Match[Match.CurrentTurn].Player == Player) then return end
	
	-- Set Board Cell
	Board[tonumber(Cell)] = Match.CurrentTurn
	
	-- Checks Board if there is a winner 
	local WinnerResult: {}? = TicTacToe.CheckBoardIfWinner(Board, Match.CurrentTurn)
	if WinnerResult then
		self:EndMatch(MatchID, Match.CurrentTurn, WinnerResult)
	end

	-- If All Cells are Occupied and There is Still No Winner Then We Set Match to Draw 
	if TicTacToe.IsBoardFull(Board) and not Match.Ended then
		self:EndMatch(MatchID)
	end
	
	-- Get Next In Turn and Set 
	local NextinTurn: string = (Match.CurrentTurn == "PLAYER_1") and "PLAYER_2" or "PLAYER_1"
	Match.CurrentTurn = NextinTurn
	
	-- Send To Players The Updated Match Data 
	self.Client.UpdateBoard:FireFor({Match["PLAYER_1"].Player, Match["PLAYER_2"].Player}, Match)
end

-- Ends match and declares winner if there is one 
function MatchService:EndMatch(MatchID: number, Winner: string, WinningCombination: {})
	-- Get Match 
	local Match: {} = Matches[MatchID]
	
	-- If There is no Winner Then its a Draw
	if not Winner then 
		self.Client.MatchEnd:FireFor({Match.PLAYER_1.Player, Match.PLAYER_2.Player}, "Draw")
		
		-- Give Player Exp 
		LevelService:IncrementExp(Match.PLAYER_1.Player, "Draw")
		LevelService:IncrementExp(Match.PLAYER_2.Player, "Draw")
	else 
		-- Get Loser 
		local Loser: string = (Winner == "PLAYER_1") and "PLAYER_2" or "PLAYER_1"

		-- Tell Match Players Who Won and Lost 
		self.Client.MatchEnd:Fire(Match[Winner].Player, "Win", WinningCombination)
		self.Client.MatchEnd:Fire(Match[Loser].Player, "Lose", WinningCombination)
		
		-- Reward Winner 
		DataService:Increment(Match[Winner].Player, "Wins", 1)
		
		-- Give Player Exp
		LevelService:IncrementExp(Match[Winner].Player, "Win")
		LevelService:IncrementExp(Match[Loser].Player, "Lose")
	end
	
	-- Set Match Ended 
	Match.Ended = true 
	
	-- Clean Match
	if Matches[MatchID] then
		Matches[MatchID] = nil
	end
end

-- Checks Match Table If Player Is In A Match 
function MatchService:IsPlayerInMatch(Player: Player): boolean
	for _, match in Matches do
		for dataName, matchData in match do
			if not (dataName == "PLAYER_1" or dataName == "PLAYER_2") then continue end
			if matchData.Player == Player then 
				return match
			end
		end
	end
end

-- 
function MatchService:KnitInit()
	-- Gets If Player is PLAYER_1 or PLAYER_2
	local function GetMatchPlayer(Player: Player, Match: {})
		for dataName, matchData in Match  do
			if not (dataName == "PLAYER_1" or dataName == "PLAYER_2") then continue end
			if matchData.Player ==  Player then
				return dataName
			end
		end
	end
	
	-- Checks if Player Who Left is in a match 
	Players.PlayerRemoving:Connect(function(Player: Player)
		-- Check if in a match 
		local IsInMatch: boolean = self:IsPlayerInMatch(Player)
		if not IsInMatch then return end
		
		-- Get Winner 
		local MatchPlayer: string = GetMatchPlayer(Player, IsInMatch)
		local Winner: string = (MatchPlayer == "PLAYER_1") and "PLAYER_2" or "PLAYER_1"
		
		-- Declare Winner For Player Left in the Match 	
		self:EndMatch(IsInMatch.ID, Winner)
	end)
end

function MatchService:KnitStart()
	-- Get Knit Services
	DataService = Knit.GetService("DataService")
	LevelService = Knit.GetService("LevelService")
	
	-- Connect Signals  
	self.Client.CheckBoard:Connect(function(...)
		self:CheckBoard(...)
	end)
end


return MatchService
