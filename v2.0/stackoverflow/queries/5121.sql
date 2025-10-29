-- {"query": "5121.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 961}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(rap.Score) AS ScoreSum,
    AVG(rap.ViewCount) AS AvgViews,
    MAX(rap.LastActivityDate) AS LastActive
  FROM RecentActivePosts rap
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(COALESCE(rap.Tags, ''), '><')) AS tagname
  ) tg
  JOIN Tags t ON t.TagName = tg.tagname
  GROUP BY t.TagName
),
AggVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedByOriginator
  FROM Votes v
  GROUP BY v.PostId
),
PostWithDerived AS (
  SELECT
    rap.Id,
    rap.Title,
    rap.CreationDate,
    rap.OwnerUserId,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    rap.LastActivityDate,
    rap.PostTypeId,
    rap.AcceptedAnswerId,
    rap.ParentId,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.Body,
    COALESCE(av.UpVotes,0) AS UpVotes,
    COALESCE(av.DownVotes,0) AS DownVotes,
    COALESCE(av.AcceptedByOriginator,0) AS AcceptedByOriginator,
    CASE
      WHEN rap.PostTypeId = 1 AND rap.AcceptedAnswerId IS NOT NULL THEN 1
      ELSE 0
    END AS HasAcceptedAnswer,
    CASE
      WHEN rap.ViewCount > 0 THEN rap.ViewCount
      ELSE 1
    END AS EffectiveViews
  FROM RecentActivePosts rap
  LEFT JOIN AggVotes av ON av.PostId = rap.Id
),
TagEngagement AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    SUM(pe.Score) AS ScoreSum
  FROM PostWithDerived pe
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(COALESCE(pe.Tags, ''), '><')) AS tagname
  ) tg
  JOIN Tags t ON t.TagName = tg.tagname
  GROUP BY t.TagName
),
Final AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.PostTypeId,
    p.Tags,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    COALESCE(av.UpVotes,0) AS UpVotes,
    COALESCE(av.DownVotes,0) AS DownVotes,
    COALESCE(av.AcceptedByOriginator,0) AS AcceptedByOriginator,
    CASE WHEN p.PostTypeId = 1 THEN (CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) ELSE 0 END AS IsAnswered,
    ta.TagName,
    ta.ScoreSum AS TagScoreSum,
    ta.AvgViews AS TagAvgViews,
    ta.LastActive AS TagLastActive
  FROM PostWithDerived p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN AggVotes av ON av.PostId = p.Id
  LEFT JOIN LATERAL (
    SELECT t2.TagName, tt.ScoreSum, tt.AvgViews, tt.LastActive
    FROM (
      SELECT unnest(string_to_array(COALESCE(p.Tags, ''), '><')) AS tagname
    ) tg
    JOIN Tags t2 ON t2.TagName = tg.tagname
    LEFT JOIN TopTags tt ON tt.TagName = t2.TagName
    LIMIT 1
  ) ta ON true
  WHERE p.PostTypeId IN (1,2)
  ORDER BY p.LastActivityDate DESC
  LIMIT 100
)
SELECT
  Id,
  Title,
  OwnerName,
  CreationDate,
  PostTypeId,
  Score,
  ViewCount,
  LastActivityDate,
  Tags,
  UpVotes,
  DownVotes,
  AcceptedByOriginator,
  IsAnswered,
  COALESCE(TagScoreSum, 0) AS TagScoreSum,
  COALESCE(TagAvgViews, 0) AS TagAvgViews
FROM Final
ORDER BY LastActivityDate DESC, Score DESC;