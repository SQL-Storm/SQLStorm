-- {"query": "398.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 24821} 
WITH
  UserStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserName,
      u.Reputation,
      u.LastAccessDate,
      u.Location,
      u.AccountId,
      COUNT(p.Id) AS TotalPosts,
      COALESCE(SUM(p.Score), 0) AS TotalPostScore,
      COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, u.Location, u.AccountId
  ),
  UserVotes AS (
    SELECT
      p.OwnerUserId AS UserId,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesReceived
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
  ),
  UserBadges AS (
    SELECT UserId, COUNT(*) AS BadgesCount, COALESCE(STRING_AGG(Name, ', '), '') AS BadgesList
    FROM Badges
    GROUP BY UserId
  ),
  UserLinked AS (
    SELECT p.OwnerUserId AS UserId, COUNT(*) AS LinkedPosts
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    GROUP BY p.OwnerUserId
  ),
  Ranking AS (
    SELECT
      us.UserId,
      us.UserName,
      us.Reputation,
      us.LastAccessDate,
      us.Location,
      us.AccountId,
      us.TotalPosts,
      us.TotalPostScore,
      us.TotalPostViews,
      COALESCE(uv.UpVotesReceived, 0) AS UpVotesReceived,
      COALESCE(uv.DownVotesReceived, 0) AS DownVotesReceived,
      COALESCE(ub.BadgesCount, 0) AS BadgesCount,
      COALESCE(ul.LinkedPosts, 0) AS LinkedPosts,
      COALESCE(ub.BadgesList, '') AS BadgesList,
      (us.TotalPostScore * 2 +
       us.TotalPosts * 3 +
       COALESCE(uv.UpVotesReceived, 0) * 2 -
       COALESCE(uv.DownVotesReceived, 0) +
       COALESCE(ub.BadgesCount, 0) * 5 +
       COALESCE(ul.LinkedPosts, 0)) AS EngagementScore,
      CONCAT(us.UserName, ' [', COALESCE(ub.BadgesList, 'No badges'), ']') AS UserBadgeSummary
    FROM UserStats us
    LEFT JOIN UserVotes uv ON uv.UserId = us.UserId
    LEFT JOIN UserBadges ub ON ub.UserId = us.UserId
    LEFT JOIN UserLinked ul ON ul.UserId = us.UserId
  ),
  Ranked AS (
    SELECT
      r.*,
      ROW_NUMBER() OVER (
        ORDER BY EngagementScore DESC, Reputation DESC
      ) AS EngRank,
      (
        SELECT COUNT(DISTINCT t)
        FROM (
          SELECT UNNEST(string_to_array(NULLIF(substring(pp.Tags, 2, GREATEST(length(pp.Tags) - 2, 0)), ''), '><')) AS t
          FROM Posts pp
          WHERE pp.OwnerUserId = r.UserId
        ) AS tagset
      ) AS TagCount
    FROM Ranking r
  )
SELECT *
FROM Ranked
WHERE EngRank <= 200
UNION ALL
SELECT *
FROM Ranked
WHERE LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
ORDER BY EngRank
LIMIT 100;