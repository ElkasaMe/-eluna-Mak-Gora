CREATE TABLE `duel_statistics` (
  `id` int NOT NULL AUTO_INCREMENT,
  `winner_guid` int NOT NULL,
  `loser_guid` int NOT NULL,
  `duel_date` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=54 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;