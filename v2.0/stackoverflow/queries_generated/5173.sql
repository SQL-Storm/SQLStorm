-- {"query": "5173.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 642} 
WITH ranked_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY CASE
        WHEN u.Location IS NULL THEN 'unknown'
        ELSE u.Location
      END
      ORDER BY u.Reputation DESC, u.LastAccessDate DESC
    ) AS rn_by_location
  FROM Users u
),
top_locations AS (
  SELECT
    location_group,
    MAX(reputation) AS max_rep,
    AVG(reputation) AS avg_rep,
    COUNT(*) AS cnt
  FROM (
    SELECT
      CASE
        WHEN Location IS NULL THEN 'Unknown'
        WHEN LENGTH(Location) < 3 THEN 'Short'
        ELSE Location
      END AS location_group,
      Reputation
    FROM Users
  ) t
  GROUP BY location_group
)
SELECT
  ru.Id AS UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.CreationDate,
  ru.LastAccessDate,
  ru.Location,
  ru.Views,
  ru.UpVotes,
  ru.DownVotes,
  ru.ProfileImageUrl,
  ru.EmailHash,
  ru.AccountId,
  COALESCE(bt.gold_count, 0) AS GoldBadges,
  COALESCE(bt.silver_count, 0) AS SilverBadges,
  COALESCE(bt.bronze_count, 0) AS BronzeBadges,
  COALESCE(vt.vote_count, 0) AS VoteCountLast30,
  CASE
    WHEN ru.rn_by_location = 1 THEN TRUE
    ELSE FALSE
  END AS IsTopInLocation,
  tl.max_rep AS LocMaxRep,
  tl.avg_rep AS LocAvgRep,
  tl.cnt AS LocCount
FROM ranked_users ru
LEFT JOIN (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_count,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver_count,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze_count
  FROM Badges
  GROUP BY UserId
) bt ON bt.UserId = ru.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS vote_count
  FROM Votes
  WHERE CreationDate >= DATEADD(day, -30, CURRENT_DATE)
  GROUP BY PostId
) vt ON vt.PostId = (SELECT Id FROM Posts WHERE OwnerUserId = ru.Id ORDER BY CreationDate DESC LIMIT 1)
LEFT JOIN top_locations tl ON (
  CASE
    WHEN ru.Location IS NULL THEN 'Unknown'
    WHEN LENGTH(ru.Location) < 3 THEN 'Short'
    ELSE ru.Location
  END = tl.location_group
)
ORDER BY ru.Reputation DESC, ru.LastAccessDate DESC
LIMIT 100;