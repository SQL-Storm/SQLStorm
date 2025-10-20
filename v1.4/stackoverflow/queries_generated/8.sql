-- {"query": "8.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 887} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.AcceptedAnswerId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.TotalBadges, 0) AS TotalBadges
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    COUNT(*) AS RelatedCount,
    SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS LinkedCount,
    SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 0
),
ComplexCalc AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    CASE
      WHEN p.PostTypeId = 1 THEN p.ViewCount * 1.0 / NULLIF(p.Score, 0)
      ELSE NULL
    END AS PopularityIndex,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
      WHEN u.DisplayName IS NOT NULL THEN u.DisplayName
      ELSE 'User ' || CAST(p.OwnerUserId AS VARCHAR)
    END AS OwnerLabel
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate IS NOT NULL
)
SELECT
  -- Outer query returning a rich benchmark result set
  c.PostId,
  c.PostTypeId,
  c.Title,
  c.ViewCount,
  c.Score,
  c.AnswerCount,
  c.CommentCount,
  c.Tags,
  c.CreationDate,
  c.LastActivityDate,
  c.PopularityIndex,
  c.OwnerLabel,
  ra.LinkedCount,
  ra.DuplicateCount,
  ue.UserId,
  ue.DisplayName AS UserDisplayName,
  ue.Reputation,
  ue.UserCreationDate,
  ue.LastAccessDate,
  ue.TotalBadges,
  ts.TagName,
  ts.Count AS TagCount,
  ca.RelatedCount,
  ca.LinkedCount AS TagLinkedCount
FROM ComplexCalc c
LEFT JOIN PostLinksAgg ca ON ca.PostId = c.PostId
LEFT JOIN TagStats ts ON ts.TagName = ANY(string_to_array(REPLACE(REPLACE(c.Tags, '<', ''), '>', ''), '><'))
LEFT JOIN RecentActivePosts rap ON rap.Id = c.PostId
LEFT JOIN UserEngagement ue ON ue.UserId = c.OwnerUserId
WHERE
  -- Complex predicates and NULL checks to exercise NULL logic and filters
  (c.ViewCount > 0 OR c.Score IS NOT NULL)
  AND (c.LastActivityDate IS NOT NULL)
  AND (CASE WHEN c.OwnerUserId IS NULL THEN TRUE ELSE ue.Reputation > 0 END)
ORDER BY
  c.LastActivityDate DESC,
  c.Score DESC,
  c.ViewCount DESC
LIMIT 100;