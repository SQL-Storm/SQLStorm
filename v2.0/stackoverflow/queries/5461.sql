WITH recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_activity AS (
  SELECT
    t.TagName,
    COUNT(*) AS post_count,
    AVG(p.ViewCount) AS avg_views,
    MAX(p.Score) AS max_score,
    SUM(p.CommentCount) AS total_comments
  FROM (
    SELECT UNNEST(string_to_array(replace(replace(p2.Tags, '<', ''), '>', ''), '<><')) AS TagName, p2.Id AS post_id
    FROM Posts p2
  ) AS t
  JOIN Posts p ON p.Id = t.post_id
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
correlated_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT c.Id) AS comment_count,
    AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS avg_bounty
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Reputation > 100
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
fast_feed AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    (CASE WHEN rp.ViewCount > 0 THEN rp.Score * 1.0 / rp.ViewCount ELSE NULL END) AS score_per_view,
    ROW_NUMBER() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.LastActivityDate DESC) AS rn,
    rp.PostTypeId
  FROM recent_posts rp
  LEFT JOIN PostLinks pl ON pl.PostId = rp.Id
  LEFT JOIN Posts rpl ON rpl.Id = pl.RelatedPostId
  WHERE rp.PostTypeId IN (1,2)
),
advanced_calc AS (
  SELECT
    fp.Id,
    fp.Title,
    fp.OwnerDisplayName,
    fp.CreationDate,
    fp.LastActivityDate,
    fp.ViewCount,
    fp.Score,
    fp.AnswerCount,
    fp.CommentCount,
    fp.score_per_view,
    fp.rn,
    fp.PostTypeId,
    (fp.Score + COALESCE((
      SELECT SUM(v2.BountyAmount)
      FROM Votes v2
      WHERE v2.PostId = fp.Id AND v2.BountyAmount IS NOT NULL
    ), 0)) / NULLIF(fp.ViewCount, 0) AS efficiency,
    (SELECT p.Tags FROM Posts p WHERE p.Id = fp.Id) AS Tags
  FROM fast_feed fp
),
final AS (
  SELECT
    ac.Id,
    ac.Title,
    ac.OwnerDisplayName,
    ac.CreationDate,
    ac.LastActivityDate,
    ac.ViewCount,
    ac.Score,
    ac.AnswerCount,
    ac.CommentCount,
    ac.score_per_view,
    ac.rn,
    ac.efficiency,
    tt.TagName,
    ac.Tags
  FROM advanced_calc ac
  LEFT JOIN Tags t ON t.WikiPostId = ac.Id OR t.ExcerptPostId = ac.Id
  LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(coalesce(ac.Tags, ''), '>')) AS TagName
  ) AS tt ON TRUE
)
SELECT
  f.Id,
  f.Title,
  f.OwnerDisplayName,
  f.CreationDate,
  f.LastActivityDate,
  f.ViewCount,
  f.Score,
  f.AnswerCount,
  f.CommentCount,
  f.score_per_view,
  f.efficiency,
  f.TagName,
  ru.UserId AS CorrelatedUserId,
  ru.UserName AS CorrelatedUserName,
  ru.Reputation AS CorrelatedUserRep
FROM final f
LEFT JOIN correlated_users ru ON TRUE
WHERE f.efficiency IS NOT NULL
ORDER BY f.LastActivityDate DESC, f.Score DESC
LIMIT 100;