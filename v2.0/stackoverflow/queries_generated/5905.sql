-- {"query": "5905.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 952} 
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '30 days')
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    p.Id AS PostId
  FROM RecentActivePosts p
  WHERE p.Tags IS NOT NULL
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
TopActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
    COUNT(DISTINCT p.Id) AS PostsCreated
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.LastAccessDate >= (CURRENT_DATE - INTERVAL '90 days')
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
BadgeActivity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesEarnedLast90d,
    STRING_AGG(b.Name, ',') AS BadgeNames
  FROM Badges b
  WHERE b.Date >= (CURRENT_DATE - INTERVAL '90 days')
  GROUP BY b.UserId
),
CorrelatedPostHistory AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment,
    ph.Text,
    ph.RevisionGUID
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 16, 52, 53) -- close, community owned, hot question signals
)
SELECT
  -- Summary row per top tag
  th.TagName,
  th.PostCount,
  ts.ScoreSum AS TotalScore,
  ts.AvgScore,
  tu.UserId AS TopContributorUserId,
  tu.DisplayName AS TopContributorName,
  tu.Reputation AS TopContributorRep,
  tu.LastAccessDate AS TopContributorLastActive,
  ba.BadgeNames AS RecentBadges,
  a.QuestionsWithCorrelations,
  ro.LastActive AS LastPostActive
FROM TagStats ts
JOIN (
  SELECT DISTINCT TagName
  FROM TopTags
) th ON true
LEFT JOIN (
  SELECT
    t.TagName,
    p.OwnerUserId AS TopUserId
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName, p.OwnerUserId
  ORDER BY COUNT(*) DESC
  LIMIT 1
) tbest ON tbest.TagName = th.TagName
LEFT JOIN TopActiveUsers tu ON tu.UserId = tbest.TopUserId
LEFT JOIN BadgeActivity ba ON ba.UserId = tu.UserId
LEFT JOIN (
  SELECT COUNT(*) AS QuestionsWithCorrelations
  FROM (
    SELECT p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.LastActivityDate > (CURRENT_TIMESTAMP - INTERVAL '14 days')
  ) q
) a ON true
LEFT JOIN (
  SELECT
    MAX(ph.CreationDate) AS LastPostActive
  FROM CorrelatedPostHistory ph
) ro ON true
ORDER BY ts.PostCount DESC
LIMIT 1;