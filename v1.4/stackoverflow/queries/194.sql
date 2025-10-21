WITH user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    MAX(p.CreationDate) AS LastActivityDate,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS OpenQuestions,
    COUNT(v.Id) AS TotalVotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
user_rank AS (
  SELECT
    ua.*,
    ROW_NUMBER() OVER (ORDER BY LastActivityDate DESC NULLS LAST, Reputation DESC) AS rn
  FROM user_activity ua
),
tag_summary AS (
  SELECT
    u.Id AS UserId,
    ARRAY_AGG(DISTINCT t.TagName) AS TagsUsed
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Tags t ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
  GROUP BY u.Id
)
SELECT
  ur.UserId,
  ur.DisplayName,
  ur.Reputation,
  ur.LastActivityDate,
  ur.TotalViews,
  ur.TotalPostScore,
  ur.TotalVotesCast,
  COALESCE(ts.TagsUsed, ARRAY[]::varchar[]) AS TagsUsed
FROM user_rank ur
LEFT JOIN tag_summary ts ON ts.UserId = ur.UserId
WHERE ur.rn <= 100
ORDER BY ur.rn;