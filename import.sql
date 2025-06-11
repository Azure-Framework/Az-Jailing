SQL schema example:
CREATE TABLE `jail_records` (
  `id` int NOT NULL AUTO_INCREMENT,
  `jailer` int NOT NULL,
  `inmate` int NOT NULL,
  `time_minutes` int NOT NULL,
  `date` datetime NOT NULL,
  `charges` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
);
