WITH 
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
TopLinkedQuestions AS (
  SELECT
    rp.Id AS QuestionId,
    COUNT(pl.Id) AS LinkedCount,
    MAX(pl.CreationDate) AS LastLinkDate
  FROM Posts rp
  LEFT JOIN PostLinks pl ON pl.PostId = rp.Id
  WHERE rp.PostTypeId = 1
  GROUP BY rp.Id
),
QuestionTagStats AS (
  SELECT
    p.Id AS QuestionId,
    t.TagName,
    t.Count AS TagCount,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY t.Count DESC) AS rn
  FROM Posts p
  JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  WHERE p.PostTypeId = 1
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    (SELECT COUNT(*) FROM Posts x WHERE x.OwnerUserId = u.Id AND x.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY) AS RecentPosts,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Date > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR) AS RecentBadges
  FROM Users u
),
Correlation AS (
  SELECT
    rp.Id AS QuestionId,
    p2.OwnerUserId AS AnswererId,
    p.Title AS QuestionTitle,
    p2.Title AS AnswerTitle,
    p.CreationDate AS QuestionCreated,
    p2.CreationDate AS AnswerCreated,
    p.Score AS QuestionScore,
    p2.Score AS AnswerScore,
    p.ViewCount AS QuestionViews,
    p2.ViewCount AS AnswerViews,
    ROW_NUMBER() OVER (PARTITION BY rp.Id ORDER BY p2.CreationDate DESC) AS rn
  FROM Posts rp
  JOIN Posts p ON p.Id = rp.ParentId OR p.Id = rp.AcceptedAnswerId
  JOIN Posts p2 ON p2.ParentId = rp.Id
  WHERE rp.PostTypeId = 1
),
Mixed AS (
  SELECT
    rp.Id AS QuestionId,
    rp.Title AS QuestionTitle,
    rp.CreationDate AS QuestionCreated,
    rp.Score AS QuestionScore,
    rp.ViewCount AS QuestionViews,
    ta.TagName,
    ta.TagCount,
    ta.rn AS TagRank,
    ua.UserId AS OwnerUserId,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ca.LinkedCount,
    ca.LastLinkDate,
    ua.RecentPosts
  FROM RecentActivePosts rp
  LEFT JOIN TopLinkedQuestions ca ON ca.QuestionId = rp.Id
  LEFT JOIN QuestionTagStats ta ON ta.QuestionId = rp.Id
  LEFT JOIN UserActivity ua ON ua.UserId = rp.OwnerUserId
  LEFT JOIN (
    SELECT
      tq.QuestionId,
      tq.LinkedCount,
      tq.LastLinkDate,
      ROW_NUMBER() OVER (PARTITION BY tq.QuestionId ORDER BY tq.LastLinkDate DESC) AS rn
    FROM TopLinkedQuestions tq
  ) cb ON cb.QuestionId = rp.Id
)
SELECT
  m.QuestionId,
  m.QuestionTitle,
  m.QuestionCreated,
  m.QuestionScore,
  m.QuestionViews,
  m.TagName,
  m.TagCount,
  m.TagRank,
  m.OwnerUserId,
  m.OwnerDisplayName,
  m.OwnerReputation,
  m.LinkedCount,
  m.LastLinkDate,
  m.RecentPosts
FROM Mixed m
WHERE m.TagRank = 1
ORDER BY m.QuestionCreated DESC
LIMIT 100
OFFSET 0;