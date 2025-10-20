-- {"query": "5.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 854} 
WITH
TrendingPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score * 0.6 + p.ViewCount * 0.4 + DATE_PART('epoch', NOW() - p.CreationDate) * -1 DESC
    ) AS rn_per_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate > NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS SumViews
  FROM Posts p
  JOIN unnest(string_to_array(p.Tags, '><')) AS t(TagName) ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  HAVING COUNT(*) > 5
),
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.Id AS HistoryId,
    ph.CreationDate AS EditDate,
    ph.UserId AS EditorUserId,
    ph.Text AS EditText,
    ph.Comment AS EditComment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (5, 8, 25) -- Edit Body / Rollback / Suggested Edit Applied
),
Combined AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    u.DisplayName AS OwnerName,
    tp.LastActivityDate,
    tp.rn_per_owner,
    ARRAY_AGG(DISTINCT tt.TagName) OVER (PARTITION BY tp.PostId) AS TopTagsList
  FROM TrendingPosts tp
  LEFT JOIN Users u ON tp.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT t.TagName
    FROM unnest(string_to_array(tp.Tags, '><')) AS t(TagName)
    LIMIT 3
  ) tt ON TRUE
),
Agg AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerName,
    c.CreationDate,
    c.Score,
    c.ViewCount,
    c.LastActivityDate,
    c.TopTagsList,
    (SELECT COUNT(*) FROM Comments co WHERE co.PostId = c.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT MAX(vt.Id) FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.PostId = c.PostId) AS LastVoteTypeId
  FROM Combined c
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerName,
  a.CreationDate,
  a.Score,
  a.ViewCount,
  a.LastActivityDate,
  a.CommentCount,
  a.UpVotes,
  a.DownVotes,
  a.TopTagsList AS TopTags,
  (SELECT STRING_AGG(CONCAT(vt.Name, '(', v.BountyAmount, ')'), ', ')
   FROM Votes v
   JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
   WHERE v.PostId = a.PostId
     AND v.VoteTypeId IN (2,6,8,9,10,11,12,14,15,16)
  ) AS VoteTrail
FROM Agg a
WHERE a.rn_per_owner = 1
ORDER BY a.LastActivityDate DESC, a.Score DESC
LIMIT 100;