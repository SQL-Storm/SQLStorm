-- {"query": "274.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 11918} 
WITH
UserKeys AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes
  FROM Users u
),
PostAgg AS (
  SELECT OwnerUserId,
         COUNT(*) AS TotalPosts,
         MAX(LastActivityDate) AS LastActivityDate
  FROM Posts
  GROUP BY OwnerUserId
),
CommentAgg AS (
  SELECT UserId,
         COUNT(*) AS TotalComments
  FROM Comments
  GROUP BY UserId
),
LastActivity AS (
  SELECT OwnerUserId, MAX(LastActivityDate) AS LastActivityDate
  FROM Posts
  GROUP BY OwnerUserId
),
BadgeAgg AS (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
)
SELECT
  uk.UserId,
  uk.DisplayName,
  uk.Reputation,
  uk.CreationDate,
  uk.LastAccessDate,
  COALESCE(uk.Location, '(unknown)') AS Location,
  uk.Views,
  uk.UpVotes,
  uk.DownVotes,
  COALESCE(pa.TotalPosts, 0) AS TotalPosts,
  COALESCE(ca.TotalComments, 0) AS TotalComments,
  la.LastActivityDate,
  COALESCE(ba.BadgeCount, 0) AS BadgeCount,
  LatestBadge.Name AS LatestBadgeName,
  (
    SELECT TOP 1 p.Title
    FROM Posts p
    WHERE p.OwnerUserId = uk.UserId
    ORDER BY p.CreationDate DESC
  ) AS LastPostTitle,
  STUFF((
    SELECT ', ' + p.Title
    FROM Posts p
    WHERE p.OwnerUserId = uk.UserId AND p.PostTypeId = 1
    ORDER BY p.CreationDate DESC
    FOR XML PATH(''), TYPE
  ).value('.', 'nvarchar(max)'), 1, 2, '') AS RecentQuestionTitles,
  COALESCE((
    SELECT SUM(p.Score)
    FROM Posts p
    WHERE p.OwnerUserId = uk.UserId
  ), 0) AS TotalPostScore,
  (
    SELECT COUNT(*)
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE p.OwnerUserId = uk.UserId AND ph.PostHistoryTypeId = 10
  ) AS ClosedVotesCount,
  CASE
    WHEN uk.Reputation IS NULL THEN 'Unknown'
    WHEN uk.Reputation >= 10000 THEN 'Legend'
    WHEN uk.Reputation >= 1000 THEN 'Superstar'
    WHEN uk.Reputation >= 100 THEN 'Guru'
    WHEN uk.Reputation >= 10 THEN 'Contributor'
    ELSE 'Newbie'
  END AS ReputationTier
FROM UserKeys uk
LEFT JOIN PostAgg pa ON pa.OwnerUserId = uk.UserId
LEFT JOIN CommentAgg ca ON ca.UserId = uk.UserId
LEFT JOIN LastActivity la ON la.OwnerUserId = uk.UserId
LEFT JOIN BadgeAgg ba ON ba.UserId = uk.UserId
OUTER APPLY (SELECT TOP 1 Name FROM Badges b WHERE b.UserId = uk.UserId ORDER BY b.Date DESC) AS LatestBadge
ORDER BY uk.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY;