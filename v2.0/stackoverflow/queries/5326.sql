-- {"query": "5326.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1001}
WITH
RecentActivePostStats AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location AS OwnerLocation,
    u.CreationDate AS OwnerCreationDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY
),
TagPopularity AS (
  SELECT
    tag AS TagName,
    COUNT(*) AS PostsInTag,
    SUM(p.ViewCount) AS ViewSum,
    SUM(p.Score) AS ScoreSum
  FROM Posts p,
       LATERAL (
         SELECT trim(both '<>' FROM t) AS tag
         FROM unnest(string_to_array(p.Tags, '><')) AS t
       ) tags
  WHERE p.PostTypeId = 1
  GROUP BY tag
),
TopTags AS (
  SELECT TagName
  FROM TagPopularity
  ORDER BY ScoreSum DESC NULLS LAST, ViewSum DESC NULLS LAST
  LIMIT 20
),
TaggedPosts AS (
  SELECT
    rap.PostId,
    rap.PostTypeId,
    rap.OwnerUserId,
    rap.Title,
    rap.Tags,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.ViewCount,
    rap.Score,
    rap.AnswerCount,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.ParentId,
    rap.AcceptedAnswerId,
    rap.OwnerReputation,
    rap.OwnerDisplayName,
    rap.OwnerLocation,
    rap.OwnerCreationDate
  FROM RecentActivePostStats rap
  JOIN TopTags tt
    ON POSITION(tt.TagName IN rap.Tags) > 0
       OR rap.Tags LIKE '%' || tt.TagName || '%'
),
CorrelatedScores AS (
  SELECT
    tp.PostId,
    tp.PostTypeId,
    tp.OwnerUserId,
    tp.Title,
    tp.Tags,
    tp.CreationDate,
    tp.LastActivityDate,
    tp.ViewCount,
    tp.Score,
    tp.AnswerCount,
    tp.CommentCount,
    tp.FavoriteCount,
    tp.ParentId,
    tp.AcceptedAnswerId,
    tp.OwnerReputation,
    tp.OwnerDisplayName,
    tp.OwnerLocation,
    tp.OwnerCreationDate,
    (tp.Score * 2 + tp.ViewCount / 10.0) AS QualityMetric
  FROM TaggedPosts tp
),
Windowed AS (
  SELECT
    cs.PostId,
    cs.PostTypeId,
    cs.OwnerUserId,
    cs.Title,
    cs.Tags,
    cs.CreationDate,
    cs.LastActivityDate,
    cs.ViewCount,
    cs.Score,
    cs.AnswerCount,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.ParentId,
    cs.AcceptedAnswerId,
    cs.OwnerReputation,
    cs.OwnerDisplayName,
    cs.OwnerLocation,
    cs.OwnerCreationDate,
    cs.QualityMetric,
    ROW_NUMBER() OVER (PARTITION BY cs.OwnerUserId ORDER BY cs.QualityMetric DESC, cs.LastActivityDate DESC) AS rn_by_owner
  FROM CorrelatedScores cs
),
Final AS (
  SELECT
    w.PostId,
    w.PostTypeId,
    w.OwnerUserId,
    w.Title,
    w.Tags,
    w.CreationDate,
    w.LastActivityDate,
    w.ViewCount,
    w.Score,
    w.AnswerCount,
    w.CommentCount,
    w.FavoriteCount,
    w.ParentId,
    w.AcceptedAnswerId,
    w.OwnerReputation,
    w.OwnerDisplayName,
    w.OwnerLocation,
    w.OwnerCreationDate,
    w.QualityMetric,
    CASE
      WHEN w.LastActivityDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7' DAY THEN 'ActiveThisWeek'
      ELSE 'ActiveOlder'
    END AS ActivityBucket
  FROM Windowed w
  WHERE w.rn_by_owner = 1
)
SELECT
  f.PostId,
  f.Title,
  f.Tags,
  f.CreationDate,
  f.LastActivityDate,
  f.ViewCount,
  f.Score,
  f.AnswerCount,
  f.CommentCount,
  f.FavoriteCount,
  f.OwnerDisplayName,
  f.OwnerReputation,
  f.ActivityBucket,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.PostId AND v.VoteTypeId = 2) AS UpVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.PostId AND v.VoteTypeId = 3) AS DownVotes,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = f.PostId) AS RelatedLinks,
  (SELECT AVG(EXTRACT(EPOCH FROM v.CreationDate)) FROM Votes v WHERE v.PostId = f.PostId) AS AvgVoteEpoch
FROM Final f
ORDER BY f.ActivityBucket, f.QualityMetric DESC
LIMIT 100;