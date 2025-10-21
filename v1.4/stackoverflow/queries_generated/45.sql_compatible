WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Body,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.PostTypeId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TagEngagement AS (
  SELECT
    t.TagName,
    COUNT(*) AS tagCount,
    SUM(p.ViewCount) AS totalViews,
    AVG(p.Score) AS avgScore
  FROM Posts p
  JOIN LATERAL (
      SELECT UNNEST(string_to_array(substr(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName
  ) AS t ON TRUE
  GROUP BY t.TagName
),
TopTagInsights AS (
  SELECT
    t.TagName,
    t.tagCount,
    t.totalViews,
    t.avgScore,
    RANK() OVER (ORDER BY t.totalViews DESC, t.avgScore DESC) AS rank
  FROM TagEngagement t
  ORDER BY t.totalViews DESC
  LIMIT 20
),
CrossJoinSummary AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerDisplayName,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.Body,
    r.LastActivityDate,
    r.CommentCount,
    r.FavoriteCount,
    r.ParentId,
    r.AcceptedAnswerId,
    r.PostTypeId,
    t.TagName AS TopTag,
    nt.avgScore AS TopTagAvgScore,
    nt.totalViews AS TopTagTotalViews
  FROM RecentTopPosts r
  LEFT JOIN TopTagInsights t ON TRUE
  LEFT JOIN (
    SELECT TagName, MAX(avgScore) AS avgScore, SUM(totalViews) AS totalViews
    FROM TopTagInsights
    GROUP BY TagName
  ) nt ON nt.TagName = t.TagName
  WHERE r.rn = 1
),
ActiveVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    u.DisplayName AS VoterName
  FROM Votes v
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14 days'
),
CrossJoinWithVotes AS (
  SELECT
    c.*,
    ARRAY_AGG(DISTINCT av.VoteTypeId) AS voteTypesThisPost
  FROM CrossJoinSummary c
  LEFT JOIN ActiveVotes av ON av.PostId = c.PostId
  GROUP BY
    c.PostId, c.Title, c.OwnerDisplayName, c.CreationDate, c.Score, c.ViewCount, c.Tags,
    c.Body, c.LastActivityDate, c.CommentCount, c.FavoriteCount, c.ParentId,
    c.AcceptedAnswerId, c.PostTypeId, c.TopTag, c.TopTagAvgScore, c.TopTagTotalViews
)
SELECT
  cj.PostId,
  cj.Title,
  cj.OwnerDisplayName,
  cj.CreationDate,
  cj.Score,
  cj.ViewCount,
  cj.Tags,
  cj.Body,
  cj.LastActivityDate,
  cj.CommentCount,
  cj.FavoriteCount,
  cj.ParentId,
  cj.AcceptedAnswerId,
  cj.PostTypeId,
  cj.TopTag,
  cj.TopTagAvgScore,
  cj.TopTagTotalViews,
  cj.voteTypesThisPost AS RelevantVoteTypes
FROM CrossJoinWithVotes cj
ORDER BY cj.CreationDate DESC, cj.Score DESC
LIMIT 100;