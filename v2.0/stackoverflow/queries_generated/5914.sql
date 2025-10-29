-- {"query": "5914.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 704} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagTotal
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
),
corr_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    u.LastAccessDate
  FROM Users u
),
complex_result AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    ru.DisplayName AS OwnerDisplayName,
    rq.ViewCount,
    rq.Score,
    rq.CommentCount,
    rq.AnswerCount,
    COALESCE(vt.Accepted, 0) AS IsAccepted,
    pt.Name AS PostTypeName,
    array_to_string(
      ARRAY(
        SELECT t.TagName
        FROM unnest(string_to_array(rq.Tags, '><')) AS t
        WHERE t <> ''
      ),
      ','
    ) AS TagsList,
    ROW_NUMBER() OVER (PARTITION BY rq.OwnerUserId ORDER BY rq.ViewCount DESC) AS OwnerViewsRank
  FROM recent_questions rq
  LEFT JOIN Posts p2 ON p2.ParentId = rq.PostId
  LEFT JOIN (
    SELECT p.Id AS PostId, MAX(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS Accepted
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 1
    GROUP BY p.Id
  ) vt ON vt.PostId = rq.PostId
  LEFT JOIN PostTypes pt ON pt.Id = 1
  LEFT JOIN corr_user ru ON ru.UserId = rq.OwnerUserId
  WHERE rq.OwnerUserId IS NOT NULL
)
SELECT
  cr.PostId,
  cr.Title,
  cr.CreationDate,
  cr.OwnerUserId,
  cr.OwnerDisplayName,
  cr.ViewCount,
  cr.Score,
  cr.CommentCount,
  cr.AnswerCount,
  cr.IsAccepted,
  cr.PostTypeName,
  cr.TagsList,
  cr.OwnerViewsRank,
  ARRAY(
    SELECT json_build_object('Tag', t.TagName, 'Count', t2.Count)
    FROM (
      SELECT unnest(string_to_array(cr.TagsList, ',')) AS TagName
    ) t
    LEFT JOIN TopTagsAll t2 ON t2.TagName = t.TagName
  ) AS TagStats
FROM complex_result cr
ORDER BY cr.ViewCount DESC NULLS LAST, cr.Score DESC NULLS LAST
LIMIT 100;