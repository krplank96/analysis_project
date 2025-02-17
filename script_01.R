rm(list = ls())

pacman::p_load(tidyverse, magrittr, janitor, readxl,
               lubridate, ggplot2, scales, stargazer, 
               dplyr, ggrepel, ggalt, tidyr, plotly, 
               gganimate, gifski, zoo,  
               RSQLite, ggdark, showtext, mosaic,
               reactable, kableExtra, patchwork)



`%out%` = Negate(`%in%`)

# Source for Valorant Pro Matches
# https://www.kaggle.com/visualize25/valorant-pro-matches-full-data

## connect to db
con <- dbConnect(drv=RSQLite::SQLite(), dbname="data/valorant.sqlite")

## list all tables
tables <- dbListTables(con)

## exclude sqlite_sequence (contains table information)
tables <- tables[tables != "sqlite_sequence"]

l_data_frames <- vector("list", length=length(tables))

## create a data.frame for each table
for (i in seq(along=tables)) {
  l_data_frames[[i]] <- dbGetQuery(conn=con, statement=paste("SELECT * FROM '", tables[[i]], "'", sep=""))
 
  }

# Notes: data breakdown
# 1 round history and team ids
# 2 player by game
# 3 match round win information
# 4 event stats



# Questions we want to answer
# how important is full buying to win an eco
# what amount of investment yields the highest return on a force
# naming lists
round_list = paste0("r", seq(1:50))
info_list = c("RoundWinner", "ScoreAfterRound", "WinType", "Team1Bank", "Team2Bank", "Team1BuyType", "Team2BuyType")
info_list_gsub_list = "RoundWinner|ScoreAfterRound|WinType|Team1Bank|Team2Bank|Team1BuyType|Team2BuyType"
extra_char_list = "'|:| |\\{|\\}"

#match info clean up
match_info_df = l_data_frames[[3]] %>%
  as.data.frame() %>% 
  clean_names() %>%
  select(game_id, match_id, map, team1id, team2id, 
         team1, team2, winner, team1_side_first_half)


# lets clean up our round histories
round_history_df = l_data_frames[[1]] %>%
  as.data.frame() %>% 
  clean_names() %>%
  filter(!is.na(round_history)) %>%
  separate(round_history, round_list, sep = ", \\d{1,2}:") %>%
  pivot_longer(
    cols = starts_with("r"),
    names_to = "round",
    values_to = "info"
  ) %>%
  filter(!is.na(info)) %>%
  mutate(info = gsub(info_list_gsub_list, "", info)) %>%
  mutate(info = gsub(extra_char_list, "", info)) %>%
  separate(info, info_list, sep = ",") %>%
  clean_names() %>% 
  mutate(round = as.numeric(gsub("r", "", round)), 
         round_winner = gsub("\\d", "", round_winner),
         team1bank = as.numeric(team1bank),
         team2bank = as.numeric(team2bank)) %>%
  mutate(round_tpye = ifelse(round == 1 | round == 13, "pistol", "other")) %>%
  left_join(match_info_df) %>% # join with match info
  separate(score_after_round, c("team1_rounds", "team2_rounds"), sep = "-") %>%
  mutate(team1_rounds = as.numeric(team1_rounds),
         team2_rounds = as.numeric(team2_rounds),
         team1_winner_dummy = ifelse(winner == team1, 1, 0)) %>%
  mutate(round_difference = team1_rounds - team2_rounds)

# player stats
player_info_df = l_data_frames[[2]] %>%
  as.data.frame() %>% 
  clean_names() 


# What does pistol round mean for winning the game



# is the 9-3 Curse Real
# lets limit to games that have a 9-3 score line
# score at half win percentage


# for some reason team 1 wins 77% of the time
round_history_df %>% 
  mutate(score_diff_at_half = ifelse(round == 12, round_difference, NA)) %>%
  filter(!is.na(score_diff_at_half)) %>%
  summarise(team1_win_pct = mean(team1_winner_dummy, na.rm = T))

# to solve this we list each game twice, with each team as team1 and team2

# First lets make a "flipped" version of the dataframe
# We have to list each column twice to get the two to switch
round_history_df_flip = round_history_df %>% 
  mutate(game_id = paste0(game_id, "B"),
         match_id = paste0(match_id, "B")) %>% # lets add a B and an A to the game id for the duplicates
  mutate(team1id_flip = team1id,
         team2id_flip = team2id,
         team1_rounds_flip = team1_rounds,
         team2_rounds_flip = team2_rounds,
         team1bank_flip = team1bank,
         team2bank_flip = team2bank,
         team1buy_type_flip = team1buy_type,
         team2buy_type_flip = team2buy_type,
         team1_flip = team1,
         team2_flip = team2) %>%
  mutate(team1id = team2id_flip,
         team2id = team1id_flip,
         team1_rounds = team2_rounds_flip,
         team2_rounds = team1_rounds_flip,
         team1bank = team2bank_flip,
         team2bank = team1bank_flip,
         team1buy_type = team2buy_type_flip,
         team2buy_type = team1buy_type_flip,
         team1 = team2_flip,
         team2 = team1_flip) %>%
  select(-ends_with("_flip")) %>%
  mutate(team1_side_first_half = ifelse(team1_side_first_half == "attack", "defend", "attack"),
         team1_winner_dummy = ifelse(team1_winner_dummy == 1, 0, 1),
         round_difference = round_difference*-1)


round_history_df = round_history_df %>% 
  mutate(game_id = paste0(game_id, "A"),
         match_id = paste0(match_id, "A")) %>%
  rbind(round_history_df_flip) 

# delete flipped half of data sett as it is binded now
rm(round_history_df_flip)

# create a summary dataset for a plot
halftime_score_df_summary = round_history_df %>%
  mutate(score_diff_at_half = ifelse(round == 12, round_difference, NA)) %>%
  filter(!is.na(score_diff_at_half)) %>%
  group_by(score_diff_at_half, team1_side_first_half) %>%
  summarise(pct_victory = mean(team1_winner_dummy, na.rm = T)) %>%
  mutate(team1_side_first_half = ifelse(team1_side_first_half == "attack", "Attack", "Defend")) %>%
  filter(score_diff_at_half > -1) 
  


# lets fit a function to our plot
halftime_score_df_summary_sample = round_history_df %>%
  mutate(score_diff_at_half = ifelse(round == 12, round_difference, NA)) %>%
  filter(!is.na(score_diff_at_half)) #%>%
  #sample_n(round(nrow(.)/2, 0)) 

halftime_score_df_summary_test = round_history_df %>%
  mutate(score_diff_at_half = ifelse(round == 12, round_difference, NA)) %>%
  filter(!is.na(score_diff_at_half)) %>%
  #filter(game_id %out% halftime_score_df_summary_sample$game_id)  %>%
  group_by(score_diff_at_half, team1_side_first_half) %>%
  summarise(pct_victory = mean(team1_winner_dummy, na.rm = T)) %>%
  mutate(team1_side_first_half = ifelse(team1_side_first_half == "attack", "Attack", "Defend")) %>%
  filter(score_diff_at_half > -1) 

halftime_score_df_summary_sample %<>%
  group_by(score_diff_at_half, team1_side_first_half) %>%
  summarise(pct_victory = mean(team1_winner_dummy, na.rm = T)) %>%
  mutate(team1_side_first_half = ifelse(team1_side_first_half == "attack", "Attack", "Defend")) %>%
  filter(score_diff_at_half > -1) 


halftime_score_df_defend_reg = halftime_score_df_summary_sample %>%
  filter(score_diff_at_half != 6 & team1_side_first_half == "Defend")

halftime_score_df_attack_reg = halftime_score_df_summary_sample %>%
  filter(score_diff_at_half != 6 & team1_side_first_half == "Attack")


halftime_score_df_defend_reg_test = halftime_score_df_summary_test %>%
  filter(score_diff_at_half != 6 & team1_side_first_half == "Defend")

halftime_score_df_attack_reg_test = halftime_score_df_summary_test %>%
  filter(score_diff_at_half != 6 & team1_side_first_half == "Attack")


# create regressions for attack and defend
#linear regressions
reg_defend_linear <- lm(pct_victory ~ score_diff_at_half, data=halftime_score_df_defend_reg)
reg_attack_linear <- lm(pct_victory ~ score_diff_at_half, data=halftime_score_df_attack_reg)
#non linear regressions
reg_defend_non_linear_1 <- lm(pct_victory ~ score_diff_at_half + I(score_diff_at_half^2), data=halftime_score_df_defend_reg)
reg_attack_non_linear_1 <- lm(pct_victory ~ score_diff_at_half + I(score_diff_at_half^2), data=halftime_score_df_attack_reg)
#non linear regressions with cubed piece
reg_defend_non_linear_2 <- lm(pct_victory ~ score_diff_at_half + I(score_diff_at_half^2)+ I(score_diff_at_half^3), data=halftime_score_df_defend_reg)
reg_attack_non_linear_2 <- lm(pct_victory ~ score_diff_at_half + I(score_diff_at_half^2)+ I(score_diff_at_half^3), data=halftime_score_df_attack_reg)

# stargazer of model


stargazer(reg_defend_linear, reg_attack_linear, 
          reg_defend_non_linear_1, reg_attack_non_linear_1,
          reg_defend_non_linear_2, reg_attack_non_linear_2, 
          dep.var.labels = "% Victorious",
          column.labels=c("Defend","Attack", "Defend","Attack", "Defend","Attack"),
          covariate.labels = 
            c("Score Difference at Half", "core Difference at Half (Squared)", "Score Difference at Half (Cubed)"),
          type = "text")


# save predictions of the model in the new data frame 
# together with variable you want to plot against
halftime_score_df_defend = halftime_score_df_summary_test %>%
  filter(team1_side_first_half == "Defend")

predicted_defend_df <- data.frame(pct_victory_pred = predict(reg_defend_non_linear_2, halftime_score_df_defend))
predicted_defend_df = cbind(halftime_score_df_defend, predicted_defend_df)

halftime_score_df_attack = halftime_score_df_summary_test %>%
  filter(team1_side_first_half == "Attack")

predicted_attack_df <- data.frame(pct_victory_pred = predict(reg_attack_non_linear_2, halftime_score_df_attack))
predicted_attack_df = cbind(halftime_score_df_attack, predicted_attack_df)





# what does momentum do to the 9-3 curse
# ID rounds with chance of momentum
possible_momentum = round_history_df %>%
  group_by(game_id) %>%
  arrange(game_id, round) %>%
  mutate(two_round_lag = lag(round_difference, 2)) %>%
  mutate(score_diff_at_half = ifelse(round == 12, round_difference, NA)) %>%
  filter(!is.na(score_diff_at_half)) %>%
  mutate(
    momentum_dummy = case_when(
      two_round_lag == -8 & round_difference == -6 ~ "Comeback", # 1-9 to 3-9
      two_round_lag == 8 & round_difference == 6 ~ "Comeback", # 9-1 to 9-3 
      two_round_lag == -6 & round_difference == -4 ~ "Comeback", # 2-8 to 4-8
      two_round_lag == 6 & round_difference == 4 ~ "Comeback", # 8-2 to 8-4
      two_round_lag == -4 & round_difference == -2 ~ "Comeback", # 3-7 to 5-7
      two_round_lag == 4 & round_difference == 2 ~ "Comeback", # 7-3 to 7-5
      two_round_lag == -10 & round_difference == -8 ~ "Comeback", # 0-10 to 2-10
      two_round_lag == 10 & round_difference == 8 ~ "Comeback", # 10-0 to 10-2
      TRUE                      ~ "No Momentum"
    )
  )
  

# summarise the momentum data
momentum_diff_summary = possible_momentum %>%
  mutate(score_line = paste0(team1_rounds, "-", team2_rounds)) %>%
  group_by(momentum_dummy, score_line, round_difference, team1_side_first_half) %>%
  summarise(pct_victory = mean(team1_winner_dummy, na.rm = T)) %>%
  mutate(team1_side_first_half = ifelse(team1_side_first_half == "attack", "Attack", "Defend")) %>%
  filter(abs(round_difference) %out% c(0, 10, 12)) %>%
  arrange(round_difference, team1_side_first_half) %>%
  pivot_wider(names_from = "momentum_dummy", values_from = "pct_victory") %>%
  ungroup() %>%
  mutate(`Momentum Difference` =  `Comeback` - `No Momentum`) %>%
  filter(round_difference < 0) %>%
  select(`Score Line` = score_line, `Start Side` = team1_side_first_half, `No Momentum`, `Comeback`, `Momentum Difference`) %>%
  mutate(`No Momentum` = paste0(round(`No Momentum`, 3)*100, "%"),
         `Comeback` = paste0(round(`Comeback`, 3)*100, "%"),
         `Momentum Difference` = paste0(round(`Momentum Difference`, 3)*100, "%"))
















img <- png::readPNG("./images/valorant_logo.png")
rast <- grid::rasterGrob(img, interpolate = T)

# font options: https://fonts.google.com/
font_add_google("Montserrat", "montserrat")  # Use the actual file path
showtext_auto()


round_diff_plot = halftime_score_df_summary %>% 
ggplot(aes(x=score_diff_at_half, y=pct_victory)) +
  annotation_custom(rast, ymin = .8, ymax = .95, xmin = -12) +
  geom_bar(stat="identity", fill="#FF4654")+
  scale_x_continuous(breaks = seq(-12, 12, 2)) +
  scale_y_continuous(labels = scales::percent_format(scale = 100)) + 
  geom_text(aes(label = paste0(round(pct_victory,3)*100, "%" )), vjust = 1.5, colour = "white") +
  ggtitle("Scoreline at Halftime vs. Win % Victorious") +
  ylab("% Victorious") +
  xlab("Round Difference at Half") +
  dark_theme_classic(base_family = "montserrat", base_size = 14) + 
  theme(
    panel.background = element_rect(fill = "#191530",
                                    colour = "#191530",
                                    size = 0.5, linetype = "solid"),
    plot.background = element_rect(fill = "#191530"),
    strip.background =element_rect(fill="#191530")
  ) +
  facet_wrap(~team1_side_first_half)
round_diff_plot




# this is the predicted line of multiple linear regression
function_plot_defend = ggplot(data = predicted_defend_df, aes(x = score_diff_at_half, y = pct_victory)) + 
  annotation_custom(rast, ymin = .6, ymax = .8, xmin = 6, xmax = 11) +
  geom_point(color='white') +
  geom_line(color="#FF4654",data = predicted_defend_df, aes(x=score_diff_at_half, y=pct_victory_pred)) + 
  scale_x_continuous(breaks = seq(-12, 12, 2)) +
  scale_y_continuous(labels = scales::percent_format(scale = 100), breaks = seq(.6, 1, .2), limits = c(.45,1.05)) + 
  ggtitle("Defense") +
  ylab("% Victorious") +
  xlab("Round Difference at Half") +
  dark_theme_classic(base_family = "montserrat", base_size = 14) + 
  theme(
    panel.background = element_rect(fill = "#191530",
                                    colour = "#191530",
                                    size = 0.5, linetype = "solid"),
    plot.background = element_rect(fill = "#191530"),
    strip.background =element_rect(fill="#191530")
  )

function_plot_attack = ggplot(data = predicted_attack_df, aes(x = score_diff_at_half, y = pct_victory)) + 
  annotation_custom(rast, ymin = .6, ymax = .8, xmin = 6, xmax = 11) +
  geom_point(color='white') +
  geom_line(color="#FF4654",data = predicted_attack_df, aes(x=score_diff_at_half, y=pct_victory_pred)) + 
  scale_x_continuous(breaks = seq(-12, 12, 2)) +
  scale_y_continuous(labels = scales::percent_format(scale = 100), breaks = seq(.6, 1, .2), limits = c(.45,1.05)) + 
  ggtitle("Attack") +
  ylab("% Victorious") +
  xlab("Round Difference at Half") +
  dark_theme_classic(base_family = "montserrat", base_size = 14) + 
  theme(
    panel.background = element_rect(fill = "#191530",
                                    colour = "#191530",
                                    size = 0.5, linetype = "solid"),
    plot.background = element_rect(fill = "#191530"),
    strip.background =element_rect(fill="#191530")
  )



function_plot_defend + function_plot_attack



# lets compare each of the points to their predicted point
predicted_defend_df %>%
  rbind(predicted_attack_df)  %>%
  mutate(Residual = abs(pct_victory - pct_victory_pred)) %>%
  rename(`Score Difference` = score_diff_at_half, `First Half Side` = team1_side_first_half,
         `% Victorious` = pct_victory, `% Victorious (Predicted)` = pct_victory_pred,
         ) %>%
  mutate(`% Victorious` = paste0(round(`% Victorious`, 4)*100, "%"),
         `% Victorious (Predicted)` = paste0(round(`% Victorious (Predicted)`, 4)*100, "%") ,
         Residual = paste0(round(Residual, 4)*100, "%") ) %>%
  kbl() %>%
  kable_material_dark()






# here we can see that going from 1-9 to 3-9 on attack adds an additional 5.4% chance of victory, pretty significant
momentum_diff_summary %>%
  kbl() %>%
  kable_material_dark()












