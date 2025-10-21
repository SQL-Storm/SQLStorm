-- {"query": "259.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10545} 
WITH PostStats AS (
  SELECT OwnerUserId,
         SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
         SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM Posts
  GROUP BY OwnerUserId
),
UserVotes AS (
  SELECT p.OwnerUserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.OwnerUserId
),
BadgeSummary AS (
  SELECT UserId, COUNT(*) AS BadgeCount, MAX(Date) AS LatestBadgeDate
  FROM Badges
  GROUP BY UserId
),
LastPost AS (
  SELECT OwnerUserId,
         Title AS LastPostTitle,
         LastActivityDate,
         ViewCount,
         ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY LastActivityDate DESC) AS rn
  FROM Posts
),
UserAll AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.LastAccessDate,
         COALESCE(ps.QuestionCount, 0) AS QuestionCount,
         COALESCE(ps.AnswerCount, 0) AS AnswerCount,
         COALESCE(uv.UpVotes, 0) AS UpVotes,
         COALESCE(uv.DownVotes, 0) AS DownVotes,
         COALESCE(bs.BadgeCount, 0) AS BadgeCount,
         bs.LatestBadgeDate,
         lp.LastPostTitle,
         lp.LastActivityDate AS LastPostActivityDate,
         lp.ViewCount AS LastPostViews,
         (COALESCE(lp.ViewCount, 0) * 0.5
          + COALESCE(uv.UpVotes, 0) * 3
          - COALESCE(uv.DownVotes, 0) * 2
          + COALESCE(ps.QuestionCount, 0) * 2) AS EngagementScore
  FROM Users u
  LEFT JOIN PostStats ps ON ps.OwnerUserId = u.Id
  LEFT JOIN UserVotes uv ON uv.OwnerUserId = u.Id
  LEFT JOIN BadgeSummary bs ON bs.UserId = u.Id
  LEFT JOIN LastPost lp ON lp.OwnerUserId = u.Id AND lp.rn = 1
)
SELECT UserId,
       DisplayName,
       Reputation,
       LastAccessDate,
       EngagementScore,
       QuestionCount,
       AnswerCount,
       UpVotes,
       DownVotes,
       BadgeCount,
       LatestBadgeDate,
       LastPostTitle,
       LastPostActivityDate,
       LastPostViews,
       LENGTH(COALESCE(LastPostTitle, '')) AS LastPostTitleLength,
       'Engagement' AS ScoreType,
       EngagementScore AS ScoreValue
FROM UserAll
UNION ALL
SELECT UserId,
       DisplayName,
       Reputation,
       LastAccessDate,
       NULL AS EngagementScore,
       QuestionCount,
       AnswerCount,
       UpVotes,
       DownVotes,
       BadgeCount,
       LatestBadgeDate,
       LastPostTitle,
       LastPostActivityDate,
       LastPostViews,
       LENGTH(COALESCE(LastPostTitle, '')) AS LastPostTitleLength,
       'Reputation' AS ScoreType,
       Reputation AS ScoreValue
FROM UserAll
ORDER BY ScoreValue DESC NULLS LAST
LIMIT 200;