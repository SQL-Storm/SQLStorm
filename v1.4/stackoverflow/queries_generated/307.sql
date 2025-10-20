-- {"query": "307.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 10468} 
WITH AllUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(p.PostCount, 0) AS PostCount,
    COALESCE(p.TotalScore, 0) AS TotalScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT MAX(p2.LastActivityDate) FROM Posts p2 WHERE p2.OwnerUserId = u.Id) AS LastActivity,
    COALESCE((
      SELECT SUM(CASE WHEN vt.Id = 2 THEN 1 WHEN vt.Id = 3 THEN -1 ELSE 0 END)
      FROM Votes v
      JOIN Posts pt ON v.PostId = pt.Id
      JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
      WHERE pt.OwnerUserId = u.Id
    ), 0) AS NetVotes,
    LEFT(UPPER(COALESCE(u.Location, 'Unknown')), 12) AS LocationToken
  FROM Users u
  LEFT JOIN (
      SELECT OwnerUserId, COUNT(*) AS PostCount, COALESCE(SUM(Score), 0) AS TotalScore
      FROM Posts
      GROUP BY OwnerUserId
  ) p ON p.OwnerUserId = u.Id
),
RankingByRep AS (
  SELECT
    UserId,
    DisplayName,
    Reputation AS PrimaryValue,
    NetVotes,
    LastActivity,
    LocationToken,
    ROW_NUMBER() OVER (ORDER BY Reputation DESC, NetVotes DESC NULLS LAST) AS Rank
  FROM AllUsers
),
RankingByBadges AS (
  SELECT
    UserId,
    DisplayName,
    BadgeCount AS PrimaryValue,
    NetVotes,
    LastActivity,
    LocationToken,
    ROW_NUMBER() OVER (ORDER BY BadgeCount DESC, NetVotes DESC NULLS LAST) AS Rank
  FROM AllUsers
)
SELECT UserId, DisplayName, 'Reputation' AS Mode, PrimaryValue, Rank, LastActivity, NetVotes, LocationToken
FROM RankingByRep
UNION ALL
SELECT UserId, DisplayName, 'Badges' AS Mode, PrimaryValue, Rank, LastActivity, NetVotes, LocationToken
FROM RankingByBadges
ORDER BY UserId, Rank
LIMIT 500;