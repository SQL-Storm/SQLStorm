WITH recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.OwnerDisplayName,
    p.LastActivityDate
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_scores AS (
  SELECT
    d.TagName,
    COUNT(d.PostId) AS PostCount,
    AVG(d.Score) AS AvgScore,
    SUM(d.ViewCount) AS TotalViews
  FROM (
    SELECT 
      unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.PostId,
      p.Score,
      p.ViewCount
    FROM recent_posts p
    WHERE p.PostTypeId = 1
  ) AS d
  JOIN Tags t ON t.TagName = d.TagName
  GROUP BY d.TagName
),
top_tags AS (
  SELECT
    ts.TagName,
    ts.PostCount,
    ts.AvgScore,
    ts.TotalViews
  FROM tag_scores ts
  ORDER BY ts.TotalViews DESC
  LIMIT 20
),
popular_authors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    SUM(rp.Score) AS ReputationWeightedScore,
    COUNT(rp.PostId) AS PostCount
  FROM recent_posts rp
  JOIN Users u ON rp.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
  ORDER BY ReputationWeightedScore DESC
  LIMIT 50
),
cross_linked AS (
  SELECT
    rp.PostId,
    cp.RelatedPostId,
    lt.Name AS LinkTypeName,
    rp.Title AS PostTitle,
    rl.Title AS RelatedPostTitle
  FROM recent_posts rp
  JOIN PostLinks cp ON cp.PostId = rp.PostId
  JOIN Posts rl ON rl.Id = cp.RelatedPostId
  LEFT JOIN LinkTypes lt ON lt.Id = cp.LinkTypeId
  WHERE rp.PostTypeId = 1
)
SELECT
  rp.PostId,
  rp.Title AS PostTitle,
  rp.OwnerUserId,
  ru.DisplayName AS OwnerDisplayName,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.Tags,
  rp.LastActivityDate,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagList,
  (CASE
     WHEN rp.ViewCount > 1000 AND rp.Score > 5 THEN true
     ELSE false
   END) AS HighEngagementFlag,
  (CASE
     WHEN rp.Score >= 0 THEN rp.Score
     ELSE 0
   END) AS NonNegativeScore,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpvotesFromVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownvotesFromVotes,
  (SELECT COUNT(*) FROM (
      SELECT unnest(string_to_array(substr(rp2.Tags, 2, length(rp2.Tags)-2), '><')) AS TagName
      FROM recent_posts rp2
      WHERE rp2.PostId = rp.PostId
    ) as s
    JOIN top_tags tt ON tt.TagName = s.TagName
  ) AS TopTagPresence
FROM recent_posts rp
LEFT JOIN Users ru ON ru.Id = rp.OwnerUserId
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS TagName
) tags_unnest ON true
LEFT JOIN Tags t ON t.TagName = tags_unnest.TagName
LEFT JOIN cross_linked cl ON cl.PostId = rp.PostId
GROUP BY
  rp.PostId, rp.Title, rp.OwnerUserId, ru.DisplayName, rp.CreationDate, rp.Score, rp.ViewCount,
  rp.Tags, rp.LastActivityDate
HAVING
  (rp.ViewCount > 100 OR rp.Score > 2)
ORDER BY rp.LastActivityDate DESC
LIMIT 100;