WITH RecentBadgedUsers AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation >= 1000
      AND u.Location IS NOT NULL
      AND (
        LOWER(u.Location) LIKE '%usa%'
        OR LOWER(u.Location) LIKE '%united kingdom%'
        OR LOWER(u.Location) LIKE '%europe,%'
      )
    GROUP BY u.Id, u.DisplayName, u.Reputation
), AnswerScoreRanks AS (
    SELECT a.OwnerUserId,
           a.Id AS AnswerId,
           a.Score,
           ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.Score DESC, a.CreationDate DESC) AS AnswerRank,
           SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) OVER (PARTITION BY a.OwnerUserId) AS AcceptedAnswerCount,
           a.CreationDate
    FROM Posts a
    LEFT JOIN Posts q ON q.AcceptedAnswerId = a.Id
    WHERE a.PostTypeId = 2
)
SELECT rbu.UserId,
       rbu.DisplayName,
       rbu.Reputation,
       rbu.GoldBadges,
       rbu.SilverBadges,
       rbu.BronzeBadges,
       rbu.LastBadgeDate,
       asr.AnswerId,
       asr.Score,
       asr.AnswerRank,
       asr.AcceptedAnswerCount
FROM RecentBadgedUsers rbu
JOIN AnswerScoreRanks asr ON asr.OwnerUserId = rbu.UserId
WHERE asr.AnswerRank <= 5
GROUP BY
  rbu.UserId,
  rbu.DisplayName,
  rbu.Reputation,
  rbu.GoldBadges,
  rbu.SilverBadges,
  rbu.BronzeBadges,
  rbu.LastBadgeDate,
  asr.AnswerId,
  asr.Score,
  asr.AnswerRank,
  asr.AcceptedAnswerCount;