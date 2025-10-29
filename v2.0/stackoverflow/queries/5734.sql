-- {"query": "5734.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 981}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.ContentLicense,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE AND t.TagName IS NOT NULL
),
TagScore AS (
  SELECT
    nt.TagName,
    nt.Count AS TagCount,
    COALESCE(COUNT(v.Id), 0) AS VotesOnTag
  FROM TopTags nt
  LEFT JOIN Posts p ON p.Tags LIKE '%' || '<' || nt.TagName || '>' || '%'
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  GROUP BY nt.TagName, nt.Count
),
ComplexQuery AS (
  SELECT
    rap.Id AS Id,
    rap.Id AS PostId,
    rap.Title,
    rap.PostTypeId,
    rap.OwnerUserId,
    rap.OwnerDisplayName,
    rap.LastEditorDisplayName,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    rap.AnswerCount,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.AcceptedAnswerId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesOnPost,
    CASE
      WHEN rap.PostTypeId = 1 THEN 'Question'
      WHEN rap.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    (SELECT ARRAY_AGG(tn) FROM (
       SELECT TRIM(BOTH '<>' FROM UNNEST(string_to_array(rap.Tags, '><'))) AS tn
    ) s) AS TagList
  FROM RecentActivePosts rap
  LEFT JOIN Votes v ON v.PostId = rap.Id
  GROUP BY
    rap.Id,
    rap.Title,
    rap.PostTypeId,
    rap.OwnerUserId,
    rap.OwnerDisplayName,
    rap.LastEditorDisplayName,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    rap.AnswerCount,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.AcceptedAnswerId,
    rap.PostTypeId,
    rap.Tags
),
PerTagAnalytics AS (
  SELECT
    ct.TagName,
    COUNT(*) AS PostCount,
    SUM(pk.UpvotesOnPost) AS SumUpvotes,
    SUM(pk.DownvotesOnPost) AS SumDownvotes,
    AVG(pk.Score) AS AvgScore,
    MAX(pk.ViewCount) AS MaxViews
  FROM (
    SELECT
      TRIM(BOTH '<>' FROM UNNEST(string_to_array(rap.Tags, '><'))) AS TagName,
      rap.Id,
      rap.Title,
      rap.PostTypeId,
      rap.OwnerUserId,
      rap.OwnerDisplayName,
      rap.LastEditorDisplayName,
      rap.CreationDate,
      rap.LastActivityDate,
      rap.Score,
      rap.ViewCount,
      rap.Tags,
      rap.AnswerCount,
      rap.CommentCount,
      rap.FavoriteCount,
      rap.AcceptedAnswerId,
      rap.UpvotesOnPost,
      rap.DownvotesOnPost,
      rap.PostKind,
      rap.TagList
    FROM ComplexQuery rap
  ) AS ct
  LEFT JOIN ComplexQuery pk ON pk.Id = ct.Id
  GROUP BY ct.TagName
),
FinalBridge AS (
  SELECT
    pq.Id AS PostId,
    pq.Title,
    pq.PostTypeId,
    pq.OwnerUserId,
    uq.DisplayName AS OwnerDisplayName,
    pq.LastActivityDate,
    pq.Score,
    pq.ViewCount,
    pq.Tags,
    pq.AcceptedAnswerId,
    pa.TagName,
    pa.SumUpvotes,
    pa.SumDownvotes,
    pa.AvgScore
  FROM ComplexQuery pq
  LEFT JOIN PerTagAnalytics pa ON pa.TagName = (
    SELECT TRIM(BOTH '<>' FROM x.TagName) FROM (SELECT UNNEST(string_to_array(pq.Tags, '><')) AS TagName) AS x LIMIT 1
  )
  LEFT JOIN Users uq ON pq.OwnerUserId = uq.Id
)
SELECT
  fb.PostId,
  fb.Title,
  fb.PostTypeId,
  fb.OwnerUserId,
  fb.OwnerDisplayName,
  fb.LastActivityDate,
  fb.Score,
  fb.ViewCount,
  fb.Tags,
  fb.AcceptedAnswerId,
  fb.TagName,
  fb.SumUpvotes,
  fb.SumDownvotes,
  fb.AvgScore
FROM FinalBridge fb
ORDER BY fb.LastActivityDate DESC
LIMIT 100;