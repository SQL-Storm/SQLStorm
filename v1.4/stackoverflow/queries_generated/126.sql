-- {"query": "126.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2239} 
WITH
UserPostStats AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Posts p
  GROUP BY p.OwnerUserId
),
UserVotes AS (
  SELECT
    v.UserId,
    COUNT(*) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  GROUP BY v.UserId
),
UserBadges AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
TopTagUsage AS (
  SELECT
    p.OwnerUserId AS UserId,
    t.TagName AS TopTag,
    COUNT(*) AS TagUsage
  FROM Posts p
  LEFT JOIN Tags t ON t.Id = (
    CASE
      WHEN POSITION('<' IN p.Tags) > 0 THEN  (SELECT Id FROM Tags WHERE TagName = t.TagName LIMIT 1)
      ELSE NULL
    END
  )
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId, t.TagName
),
MaxTopTag AS (
  SELECT
    UserId,
    TopTag,
    TagUsage
  FROM (
    SELECT
      UserId,
      TopTag,
      TagUsage,
      ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsage DESC, TopTag ASC) AS rn
    FROM TopTagUsage
  ) AS t
  WHERE rn = 1
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(sp.PostCount, 0) AS PostCount,
  COALESCE(sp.ScoreSum, 0) AS ScoreSum,
  COALESCE(vs.TotalVotes, 0) AS TotalVotes,
  COALESCE(vs.UpVotes, 0) AS UpVotes,
  COALESCE(vs.DownVotes, 0) AS DownVotes,
  COALESCE(bd.GoldBadges, 0) AS GoldBadges,
  COALESCE(bd.SilverBadges, 0) AS SilverBadges,
  COALESCE(bd.BronzeBadges, 0) AS BronzeBadges,
  tt.TopTag,
  COALESCE(tt.TagUsage, 0) AS TagUsage
FROM Users u
LEFT JOIN UserPostStats sp ON sp.UserId = u.Id
LEFT JOIN UserVotes vs ON vs.UserId = u.Id
LEFT JOIN UserBadges bd ON bd.UserId = u.Id
LEFT JOIN MaxTopTag tt ON tt.UserId = u.Id
ORDER BY ScoreSum DESC NULLS LAST, UpVotes - DownVotes DESC NULLS LAST
LIMIT 100;