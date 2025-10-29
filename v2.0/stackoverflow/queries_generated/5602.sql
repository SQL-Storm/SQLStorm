-- {"query": "5602.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 917} 
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
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_scores AS (
  SELECT
    t.TagName,
    COUNT(p.PostId) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
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
  GROUP BY t.TagName
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
    SUM(p.Score) AS ReputationWeightedScore,
    COUNT(p.Id) AS PostCount
  FROM recent_posts rp
  JOIN Users u ON rp.OwnerUserId = u.Id
  JOIN Posts p ON p.Id = rp.PostId
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
  -- top by views and score with complex predicates
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
  -- correlate with top tags
  (SELECT COUNT(*) FROM unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS TagName
   JOIN top_tags tt ON tt.TagName = TagName
   WHERE rp.PostId = rp.Id) AS TopTagPresence
FROM recent_posts rp
LEFT JOIN Users ru ON ru.Id = rp.OwnerUserId
LEFT JOIN Tags t ON t.TagName = ANY(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><'))
LEFT JOIN cross_linked cl ON cl.PostId = rp.PostId
GROUP BY
  rp.PostId, rp.Title, rp.OwnerUserId, ru.DisplayName, rp.CreationDate, rp.Score, rp.ViewCount,
  rp.Tags, rp.LastActivityDate
HAVING
  (rp.ViewCount > 100 OR rp.Score > 2)
ORDER BY rp.LastActivityDate DESC
LIMIT 100;