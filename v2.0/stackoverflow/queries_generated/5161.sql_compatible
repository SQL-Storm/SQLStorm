WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.ParentId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.Views,
    NULLIF(p.Body, '') AS BodyContent,
    AVG(p.Score) OVER (
      ORDER BY p.CreationDate
      ROWS BETWEEN 99 PRECEDING AND CURRENT ROW
    ) AS RunningAvgScoreLast100,
    (
      SELECT COUNT(*) FROM Posts AS a
      WHERE a.ParentId = p.Id
    ) AS AnswerCountCorrelated
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
expanded_links AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Title,
    rp.Tags,
    rp.OwnerUserId,
    rp.ParentId,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    rp.OwnerReputation,
    rp.OwnerDisplayName,
    rp.AccountId,
    rp.LastAccessDate,
    rp.Location,
    rp.WebsiteUrl,
    rp.Views,
    rp.BodyContent,
    rp.RunningAvgScoreLast100,
    rp.AnswerCountCorrelated,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    pl.RelatedPostId,
    rp.Title AS RelatedPostTitle
  FROM ranked_posts rp
  LEFT JOIN PostLinks pl ON pl.PostId = rp.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  LEFT JOIN Posts rp2 ON pl.RelatedPostId = rp2.Id
),
tag_stats AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.Views,
    rp.Score,
    rp.AnswerCountCorrelated,
    rp.RunningAvgScoreLast100,
    rp.Tags,
    (SELECT COUNT(*) FROM Posts c WHERE c.ParentId = rp.PostId AND c.PostTypeId = 2) AS UndeletedChildAnswers,
    (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = rp.PostId) AS CommentCount
  FROM expanded_links rp
),
window_pair AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.ParentId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.Views,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC, p.Id ASC) AS rn_desc,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate ASC, p.Id DESC) AS rn_asc
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
)
SELECT
  ts.PostId,
  ts.Title,
  ts.OwnerDisplayName,
  ts.OwnerReputation,
  ts.Views,
  ts.Score,
  ts.AnswerCountCorrelated AS CorrelatedAnswerCount,
  ts.RunningAvgScoreLast100,
  ts.Tags,
  ws.RelatedPostId,
  ws.RelatedPostTitle,
  ws.LinkTypeName,
  ts.UndeletedChildAnswers,
  ts.CommentCount AS CommentCountTotal,
  CASE
    WHEN ts.Score IS NULL THEN 0
    ELSE ts.Score * 1.0
  END AS ScoreNormalized,
  CASE
    WHEN ts.OwnerReputation < 100 THEN 'Low'
    WHEN ts.OwnerReputation < 1000 THEN 'Medium'
    ELSE 'High'
  END AS ReputationBand,
  LENGTH(ts.Title) AS TitleLength,
  CASE
    WHEN ts.OwnerDisplayName IS NULL THEN 'Anonymous'
    WHEN ts.OwnerDisplayName <> '' THEN ts.OwnerDisplayName
    ELSE 'Anonymous'
  END AS EffectiveOwnerDisplayName
FROM tag_stats ts
LEFT JOIN window_pair wp ON wp.PostId = ts.PostId
LEFT JOIN (
  SELECT
    PostId,
    MAX(RelatedPostId) AS RelatedPostId,
    MAX(LinkTypeName) AS LinkTypeName,
    MAX(Title) AS RelatedPostTitle
  FROM expanded_links
  GROUP BY PostId
) ws ON ws.PostId = ts.PostId
WHERE ts.AnswerCountCorrelated > 0 OR ts.UndeletedChildAnswers IS NOT NULL
ORDER BY ts.RunningAvgScoreLast100 DESC, ts.Views DESC, ts.Score DESC
LIMIT 100;