-- {"query": "5157.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1039} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    COUNT(DISTINCT c.Id) OVER (PARTITION BY p.Id) AS CommentCountFromComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotesForPost
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
),
tag_expansion AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.Tags,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.PostTypeId,
    rp.ContentLicense,
    rp.Reputation,
    rp.OwnerDisplayName,
    rp.OwnerCreationDate,
    rp.OwnerLastAccessDate,
    rp.CommentCountFromComments,
    rp.UpVotesForPost,
    rp.DownVotesForPost,
    -- create a dynamic tag list by expanding the Tags field (StackOverflow style)
    array_to_string(string_to_array(rp.Tags, '><'), ',') AS ExpandedTagList
  FROM ranked_posts rp
),
latest_activity AS (
  SELECT
    te.PostId,
    te.Title,
    te.CreationDate,
    te.Score,
    te.ViewCount,
    te.OwnerUserId,
    te.Tags,
    te.LastActivityDate,
    te.CommentCount,
    te.AnswerCount,
    te.FavoriteCount,
    te.PostTypeId,
    te.ContentLicense,
    te.Reputation,
    te.OwnerDisplayName,
    te.OwnerCreationDate,
    te.OwnerLastAccessDate,
    te.CommentCountFromComments,
    te.UpVotesForPost,
    te.DownVotesForPost,
    te.ExpandedTagList,
    -- compute a windowed metric: moving average of score over last 7 posts by the same user
    AVG(te.Score) OVER (PARTITION BY te.OwnerUserId ORDER BY te.LastActivityDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS AvgScoreLast7
  FROM tag_expansion te
),
cte_enriched AS (
  SELECT
    la.*,
    -- correlation subquery: latest accepted answer id for the post if any
    (SELECT a.Id FROM Posts a WHERE a.ParentId = la.PostId AND a.PostTypeId = 2 ORDER BY a.CreationDate DESC LIMIT 1) AS LastAnswerId,
    -- left join to count related links of type 1 (Linked) and 3 (Duplicate)
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = la.PostId AND pl.LinkTypeId IN (1,3)) AS LinkCountLinkedOrDup,
    -- left join to fetch total tag count from Tags table for this tag (if any)
    (SELECT COUNT(*) FROM Tags t WHERE t.TagName = ANY(string_to_array(REPLACE(REPLACE(la.Tags, '<', ''), '>', ''), '><'))) AS TagCountMetainfo
  FROM latest_activity la
)
SELECT
  Id AS PostId,
  Title,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerDisplayName,
  Reputation AS OwnerReputation,
  OwnerCreationDate,
  OwnerLastAccessDate,
  Tags,
  ExpandedTagList,
  CommentCount,
  AnswerCount,
  FavoriteCount,
  PostTypeId,
  ContentLicense,
  AvgScoreLast7,
  LastAnswerId,
  LinkCountLinkedOrDup,
  TagCountMetainfo,
  -- complex calculation: a synthetic quality score combining several factors
  (CASE WHEN ViewCount > 0 THEN (Score * 1.0) / NULLIF(ViewCount,0) ELSE 0 END)
  + (CASE WHEN Reputation > 1000 THEN 2 ELSE 0 END)
  + (CASE WHEN LastActivityDate > CreationDate THEN 1 ELSE 0 END) AS QualityScore
FROM cte_enriched
 ORDER BY QualityScore DESC, LastActivityDate DESC
LIMIT 100;