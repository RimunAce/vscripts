if (!Entities.FindByName(null, "doublejump_timer")) {
    SpawnEntityFromTable("logic_timer", {
        targetname = "doublejump_timer",
        RefireTime = 0.05,
        OnTimer = "!self,RunScriptCode,RespireDoubleJump.Think()"
    });
}

if (!Entities.FindByName(null, "doublejump_cleanup_timer")) {
    SpawnEntityFromTable("logic_timer", {
        targetname = "doublejump_cleanup_timer",
        RefireTime = 30.0,
        OnTimer = "!self,RunScriptCode,RespireDoubleJump.PeriodicCleanup()"
    });
}

::RespireDoubleJump <- {
    Config = {
        SOUND = {
            JUMP = "player/jumplanding_zombie.wav"
        },

        JUMP_SETTINGS = {
            BASE_FORCE = 270,
            MIN_FORCE = 200,
            MAX_FORCE = 350,
            HEALTH_SCALING = false,
            MAX_JUMPS = 1
        },

        TIMING = {
            THINK_INTERVAL = 0.05,
            CLEANUP_INTERVAL = 30.0,
            JUMP_DELAY = 0.05
        },

        REQUIREMENTS = {
            MIN_HEALTH = 15,
            ALLOW_WHILE_CROUCHED = false
        },

        DEBUG = {
            ENABLED = false
        },

        CONSTANTS = {
            IN_JUMP = 2,
            INVALID_GROUND_ENTITY = -1
        }
    },

    PLAYER_STATE = {},
    AIRBORNE_PLAYERS = {},

    function Log(message, level = "DEBUG") {
        if (this.Config.DEBUG.ENABLED || level != "DEBUG") {
            printl("[Double Jump " + level + "] " + message);
        }
    },


    function OnGameEvent_player_jump(params) {
        this.HandlePlayerJump(params.userid);
    },

    function OnGameEvent_player_falldamage(params) {
        this.HandlePlayerLand(params.userid);
    },

    function OnGameEvent_player_spawn(params) {
        local player = GetPlayerFromUserID(params.userid);
        if (player && player.IsSurvivor()) {
            this.InitPlayerState(params.userid);
        }
    },

    function OnGameEvent_player_death(params) {
        if ("userid" in params) {
            local userID = params.userid;
            local player = GetPlayerFromUserID(userID);

            if (player && player.IsSurvivor()) {
                this.CleanupPlayerState(userID);
                this.Log("Cleaned up state for dead survivor: " + userID);
            }
        }
    },


    function InitPlayerState(userID) {
        this.PLAYER_STATE[userID] <- {
            canDoubleJump = true,
            hasDoubleJumped = false,
            initialJumpTime = Time(),
            lastJumpButtonState = false,
            currentJumpButtonState = false,
            loggedGroundStatus = false,
            lastActivityTime = Time(),
            jumpCount = 0
        };
        this.Log("UserID's State Initialized: " + userID);
    }

    function CleanupPlayerState(userID) {
        if (userID in this.PLAYER_STATE) {
            delete this.PLAYER_STATE[userID];
        }
        if (userID in this.AIRBORNE_PLAYERS) {
            delete this.AIRBORNE_PLAYERS[userID];
        }
        this.Log("Player state cleaned up: " + userID);
    },

    function ResetPlayerState(userID) {
        local player = GetPlayerFromUserID(userID);
        if (this.IsValidPlayer(player)) {
            this.PLAYER_STATE[userID] = {
                canDoubleJump = true,
                hasDoubleJumped = false,
                initialJumpTime = 0,
                lastJumpButtonState = false,
                currentJumpButtonState = false,
                loggedGroundStatus = true,
                lastActivityTime = Time(),
                jumpCount = 0
            };
            this.Log("Reset state for inactive player: " + userID);
        } else {
            this.CleanupPlayerState(userID);
        }
    },


    function HandlePlayerJump(userID) {
        local player = GetPlayerFromUserID(userID);
        if (!player || !player.IsSurvivor()) {
            this.Log("Invalid player or not a survivor in [HandlePlayerJump] for userID: " + userID, "WARNING");
            return;
        }

        if (!(userID in this.PLAYER_STATE)) {
            this.InitPlayerState(userID);
        }

        local state = this.PLAYER_STATE[userID];
        state.initialJumpTime = Time();
        state.canDoubleJump = player.GetHealth() > this.Config.REQUIREMENTS.MIN_HEALTH;
        state.hasDoubleJumped = false;
        state.loggedGroundStatus = false;
        state.lastActivityTime = Time();
        this.AIRBORNE_PLAYERS[userID] <- true;
        this.Log("Player jumped, set state to airborne: " + userID);
    },

    function HandlePlayerLand(userID) {
        local player = GetPlayerFromUserID(userID);
        if (!this.IsValidPlayer(player)) {
            this.Log("Invalid player in [HandlePlayerLand] for userID: " + userID, "WARNING");
            this.CleanupPlayerState(userID);
            return;
        }

        if (userID in this.AIRBORNE_PLAYERS) {
            delete this.AIRBORNE_PLAYERS[userID];
            if (userID in this.PLAYER_STATE) {
                this.PLAYER_STATE[userID].lastActivityTime = Time();
                this.PLAYER_STATE[userID].canDoubleJump = true;
                this.PLAYER_STATE[userID].hasDoubleJumped = false;
            }
            this.Log("Player landed, removed state for airborne: " + userID);
        }
    },

    function HandleDoubleJump(player) {
        try {
            if (!this.IsValidPlayer(player)) return;

            local velocity = player.GetVelocity();
            local currentHealth = player.GetHealth();
            local adjustedForce = this.Config.JUMP_SETTINGS.BASE_FORCE;

            if (this.Config.JUMP_SETTINGS.HEALTH_SCALING) {
                local healthPercentage = currentHealth / player.GetMaxHealth();
                local forceRange = this.Config.JUMP_SETTINGS.MAX_FORCE - this.Config.JUMP_SETTINGS.MIN_FORCE;
                adjustedForce = this.Config.JUMP_SETTINGS.MIN_FORCE + (forceRange * healthPercentage);

                adjustedForce = max(this.Config.JUMP_SETTINGS.MIN_FORCE,
                                  min(this.Config.JUMP_SETTINGS.MAX_FORCE, adjustedForce));

                this.Log("Health-scaled jump force: " + adjustedForce + " (Health: " + currentHealth + ")", "DEBUG");
            }

            velocity.z = adjustedForce;
            player.SetVelocity(velocity);

            NetProps.SetPropFloat(player, "localdata.m_Local.m_flFallVelocity", 0.0);

            if (!EmitSoundOn(this.Config.SOUND.JUMP, player)) {
                this.Log("Failed to play double jump sound", "WARNING");
            }

            this.Log("Double Jump executed by player: " + player.GetPlayerName() + " with force: " + adjustedForce);
        } catch (error) {
            this.Log("Error in HandleDoubleJump: " + error, "ERROR");
        }
    }


    function IsPlayerMidair(player) {
        return NetProps.GetPropInt(player, "m_hGroundEntity") == this.Config.CONSTANTS.INVALID_GROUND_ENTITY;
    },

    function Think() {
        local currentTime = Time();
        local playersToRemove = [];
        local playersToUpdate = {};

        foreach (userID, _ in this.AIRBORNE_PLAYERS) {
            if (!(userID in this.PLAYER_STATE)) {
                this.InitPlayerState(userID);
                continue;
            }

            local player = GetPlayerFromUserID(userID);
            if (!this.IsValidPlayer(player)) {
                playersToRemove.append(userID);
                continue;
            }

            playersToUpdate[userID] <- {
                player = player,
                state = this.PLAYER_STATE[userID],
                buttons = player.GetButtonMask(),
                onGround = !this.IsPlayerMidair(player)
            };
        }

        foreach (userID, data in playersToUpdate) {
            local state = data.state;

            if (!("jumpCount" in state)) {
                state.jumpCount <- 0;
            }

            state.currentJumpButtonState = (data.buttons & this.Config.CONSTANTS.IN_JUMP) != 0;

            if (data.onGround) {
                if (!state.loggedGroundStatus) {
                    state.canDoubleJump = data.player.GetHealth() > this.Config.REQUIREMENTS.MIN_HEALTH;
                    state.hasDoubleJumped = false;
                    state.jumpCount = 0;
                    this.Log("Player is on ground, double jump resets: " + userID);
                    state.loggedGroundStatus = true;
                }
                playersToRemove.append(userID);
            } else {
                state.loggedGroundStatus = false;
                if (this.CheckDoubleJumpConditions(state, currentTime)) {
                    this.HandleDoubleJump(data.player);
                    state.hasDoubleJumped = true;
                    state.jumpCount++;
                    this.Log("Player has double jumped: " + userID + " (Jump count: " + state.jumpCount + ")");
                }
            }

            state.lastJumpButtonState = state.currentJumpButtonState;
            state.lastActivityTime = currentTime;
        }

        foreach (userID in playersToRemove) {
            delete this.AIRBORNE_PLAYERS[userID];
        }
    },

    function CheckDoubleJumpConditions(state, currentTime) {
        if (currentTime - state.initialJumpTime <= this.Config.TIMING.JUMP_DELAY) return false;
        return state.canDoubleJump &&
               !state.hasDoubleJumped &&
               state.currentJumpButtonState &&
               !state.lastJumpButtonState;
    },


    function IsValidPlayer(player) {
        return player &&
               player.IsValid() &&
               player.IsSurvivor() &&
               player.GetHealth() > 0 &&
               !player.IsDead() &&
               !player.IsDying() &&
               !player.IsIncapacitated();
    },

    function PeriodicCleanup() {
        local currentTime = Time();
        local playersToReset = [];

        foreach (userID, state in this.PLAYER_STATE) {
            local player = GetPlayerFromUserID(userID);
            if (!this.IsValidPlayer(player)) {
                this.CleanupPlayerState(userID);
                this.Log("Removed state for invalid player: " + userID);
            } else if (currentTime - state.lastActivityTime > this.Config.TIMING.CLEANUP_INTERVAL) {
                if (!(userID in this.AIRBORNE_PLAYERS)) {
                    playersToReset.append(userID);
                }
            }
        }

        foreach (userID in playersToReset) {
            this.ResetPlayerState(userID);
        }

        this.Log("Periodic cleanup completed. Reset " + playersToReset.len() + " inactive players.");
    },


    // Compatibility for my Dashing script. If you see this, this is yet to release.
    function DashingConnection(userID) {
        if (!(userID in this.PLAYER_STATE)) {
            this.InitPlayerState(userID);
        }

        local state = this.PLAYER_STATE[userID];
        state.initialJumpTime = Time();
        state.lastActivityTime = Time();
        this.AIRBORNE_PLAYERS[userID] <- true;
        this.Log("Player dashed, updated activity time: " + userID);
    },
}

function UpdateConfig(newSettings) {
    foreach (category, values in newSettings) {
        if (category in RespireDoubleJump.Config) {
            foreach (key, value in values) {
                if (key in RespireDoubleJump.Config[category]) {
                    RespireDoubleJump.Config[category][key] = value;
                }
            }
        }
    }
}

::RespireDoubleJump.Performance <- {
    thinkTime = 0,
    lastThinkDuration = 0,
    totalThinkCalls = 0,

    function TrackThinkPerformance() {
        local startTime = Time();
        if (this.thinkTime > 0) {
            this.lastThinkDuration = startTime - this.thinkTime;
            this.totalThinkCalls++;
        }
        this.thinkTime = startTime;
    }
}

RespireDoubleJump.Init <- function () {
    PrecacheSound(this.Config.SOUND.JUMP);
    __CollectEventCallbacks(this, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
    this.Log("Respire's Double Jump v2 Loaded", "INFO");
}

RespireDoubleJump.Init();