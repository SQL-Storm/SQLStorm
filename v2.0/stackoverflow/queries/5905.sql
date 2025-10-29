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
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    p.PostId
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
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UpvotesGiven,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS DownvotesGiven,
    COUNT(DISTINCT p.Id) AS PostsCreated
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '90' DAY)
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
  WHERE b.Date >= (CAST('2024-10-01' AS DATE) - INTERVAL '90' DAY)
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
  WHERE ph.PostHistoryTypeId IN (10, 16, 52, 53)
),
DistinctTags AS (
  SELECT DISTINCT TagName FROM TopTags
),
BestUserPerTag AS (
  SELECT
    t.TagName,
    p.OwnerUserId AS TopUserId
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName, p.OwnerUserId
),
TopPerTagRanked AS (
  SELECT
    b.TagName,
    b.TopUserId,
    COUNT(*) OVER (PARTITION BY b.TagName, b.TopUserId) AS cnt
  FROM BestUserPerTag b
),
TopPerTag AS (
  SELECT
    TagName,
    TopUserId
  FROM (
    SELECT
      TagName,
      TopUserId,
      ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY cnt DESC) AS rn
    FROM TopPerTagRanked
  ) x
  WHERE rn = 1
),
QuestionsWithCorrelations AS (
  SELECT COUNT(*) AS QuestionsWithCorrelations
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14' DAY)
),
LastPostActiveAgg AS (
  SELECT MAX(ph.CreationDate) AS LastPostActive FROM CorrelatedPostHistory ph
)
SELECT
  th.TagName,
  ts.PostCount,
  ts.ScoreSum AS TotalScore,
  ts.AvgScore,
  tu.UserId AS TopContributorUserId,
  tu.DisplayName AS TopContributorName,
  tu.Reputation AS TopContributorRep,
  tu.LastAccessDate AS TopContributorLastActive,
  ba.BadgeNames AS RecentBadges,
  a.QuestionsWithCorrelations,
  ro.LastPostActive AS LastPostActive
FROM TagStats ts
JOIN DistinctTags th ON th.TagName = ts.TagName
LEFT JOIN TopPerTag tbest ON tbest.TagName = th.TagName
LEFT JOIN TopActiveUsers tu ON tu.UserId = tbest.TopUserId
LEFT JOIN BadgeActivity ba ON ba.UserId = tu.UserId
LEFT JOIN QuestionsWithCorrelations a ON TRUE
LEFT JOIN LastPostActiveAgg ro ON TRUE
ORDER BY ts.PostCount DESC
LIMIT 1;