-- {"query": "5653.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 820}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.ViewCount AS Views,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.CommentCount,
    p.ViewCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TagPopularity AS (
  SELECT
    tag AS TagName,
    SUM(p.Score) AS ScoreSum,
    COUNT(*) AS PostCount
  FROM RecentActivePosts p,
       unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  WHERE p.PostTypeId = 1
  GROUP BY tag
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
TopEngagedPosts AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.Title,
    rp.Views,
    rp.Score,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Tags,
    ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.Views DESC, rp.LastActivityDate DESC) AS rn
  FROM RecentActivePosts rp
),
CrossPostLinkStats AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    p2.PostTypeId AS RelatedPostTypeId,
    p2.Score AS RelatedScore
  FROM PostLinks pl
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.PostId IN (SELECT PostId FROM RecentActivePosts)
),
ComplexQueryBase AS (
  SELECT
    t.TagName,
    t.ScoreSum,
    t.PostCount,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    ua.TotalScore,
    ua.TotalViews,
    b.Name AS BadgesAwarded,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.ScoreSum DESC) AS rn
  FROM TagPopularity t
  LEFT JOIN Users u ON u.DisplayName = (
    SELECT pu.DisplayName
    FROM Users pu
    WHERE pu.Id = (
      SELECT pc.OwnerUserId
      FROM Posts pc
      WHERE pc.Tags LIKE '%' || t.TagName || '%'
      ORDER BY pc.LastActivityDate DESC
      LIMIT 1
    )
    LIMIT 1
  )
  LEFT JOIN UserActivity ua ON ua.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE t.PostCount > 0
)
SELECT
  t.TagName,
  t.ScoreSum AS TagTotalScore,
  t.PostCount AS TagPostCount,
  t.UserName,
  t.Reputation,
  t.TotalScore,
  t.TotalViews,
  COALESCE(b.BadgesAwarded, t.BadgesAwarded) AS BadgesAwarded
FROM (
  SELECT *
  FROM ComplexQueryBase
  WHERE rn = 1
) t
LEFT JOIN Users u ON u.Id = t.UserId
LEFT JOIN (
  SELECT UserId, STRING_AGG(Name, ', ') AS BadgesAwarded
  FROM Badges
  GROUP BY UserId
) b ON b.UserId = u.Id
ORDER BY t.ScoreSum DESC, t.PostCount DESC
LIMIT 100;