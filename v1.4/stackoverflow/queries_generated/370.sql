-- {"query": "370.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14321} 
WITH UserMetrics AS (
  SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'User_' || CAST(u.Id AS TEXT)) AS DisplayName,
    (COALESCE(u.DisplayName, 'User_' || CAST(u.Id AS TEXT)) || ' [' || CAST(u.Id AS TEXT) || ']') AS Label,
    COALESCE(pc.PostCount365, 0) AS PostCount365,
    COALESCE((SELECT SUM(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id), 0) AS SumPostScores,
    COALESCE(v365.UpVotes365, 0) AS UpVotes365,
    COALESCE(bGold.GoldBadges, 0) AS GoldBadges
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS PostCount365
    FROM Posts
    WHERE CreationDate >= NOW() - INTERVAL '365 days'
    GROUP BY OwnerUserId
  ) pc ON pc.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS UpVotes365
    FROM Votes
    WHERE CreationDate >= NOW() - INTERVAL '365 days' AND VoteTypeId = 2
    GROUP BY UserId
  ) v365 ON v365.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) bGold ON bGold.UserId = u.Id
),
Ranked AS (
  SELECT
    UserId,
    DisplayName,
    Label,
    PostCount365,
    SumPostScores,
    UpVotes365,
    GoldBadges,
    ROW_NUMBER() OVER (ORDER BY SumPostScores DESC NULLS LAST) AS ScoreRank,
    ROW_NUMBER() OVER (ORDER BY UpVotes365 DESC NULLS LAST) AS VotesRank
  FROM UserMetrics
),
ScoreSet AS (
  SELECT UserId, DisplayName, Label, PostCount365, SumPostScores, UpVotes365, GoldBadges, ScoreRank, NULL::int AS AltRank, 'score' AS Source
  FROM Ranked
  ORDER BY ScoreRank
  LIMIT 200
),
VoteSet AS (
  SELECT UserId, DisplayName, Label, PostCount365, SumPostScores, UpVotes365, GoldBadges, NULL::int AS ScoreRank, VotesRank, 'votes' AS Source
  FROM Ranked
  ORDER BY VotesRank
  LIMIT 200
)
SELECT *
FROM ScoreSet
UNION ALL
SELECT *
FROM VoteSet
ORDER BY UserId, Source;