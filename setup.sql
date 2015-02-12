--Copyright (C) 2015 Kivanc Yazan
--See LICENSE file for more details about GNU General Public License.


CREATE DATABASE IF NOT EXISTS TwitterVotes 
	CHARACTER SET = utf8mb4
	COLLATE = utf8mb4_unicode_ci;

USE TwitterVotes;

CREATE TABLE IF NOT EXISTS `tweets` (
  `TweetID` bigint(20) NOT NULL PRIMARY KEY,
  `TweetText` mediumtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `TweetDT` datetime NOT NULL,
  `TweetApp` mediumtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `UserID` bigint(20) NOT NULL,
  `UserName` mediumtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `UserDT` datetime NOT NULL,
  `Status` mediumtext COLLATE utf8mb4_unicode_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;