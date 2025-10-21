-- {"query": "338.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 21388} 
WITH
VotesAgg AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes
  GROUP BY PostId
),
RecentQuestions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.OwnerUserId,
         COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.CommentCount,
         p.Tags,
         p.CreationDate,
         p.LastActivityDate,
         p.FavoriteCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days')
),
Expanded AS (
  SELECT
     rq.PostId,
     rq.Title,
     rq.OwnerUserId,
     rq.OwnerName,
     rq.Score,
     rq.ViewCount,
     rq.AnswerCount,
     rq.CommentCount,
     rq.Tags,
     rq.CreationDate,
     rq.LastActivityDate,
     rq.FavoriteCount,
     COALESCE(v.UpVotes, 0) AS UpVotes,
     COALESCE(v.DownVotes, 0) AS DownVotes
  FROM RecentQuestions rq
  LEFT JOIN VotesAgg v ON v.PostId = rq.PostId
),
ExpandedWithTag AS (
  SELECT
     e.PostId,
     e.Title,
     e.OwnerUserId,
     e.OwnerName,
     e.Score,
     e.ViewCount,
     e.AnswerCount,
     e.CommentCount,
     e.CreationDate,
     e.LastActivityDate,
     e.FavoriteCount,
     e.UpVotes,
     e.DownVotes,
     t.Tag AS TagName
  FROM Expanded e
  CROSS JOIN LATERAL (
     SELECT unnest(string_to_array(substring(e.Tags, 2, length(e.Tags) - 2), '><')) AS Tag
  ) t
),
RankedPerTag AS (
  SELECT
     awt.TagName,
     awt.PostId,
     awt.Title,
     awt.OwnerUserId,
     awt.OwnerName,
     awt.Score,
     awt.ViewCount,
     awt.AnswerCount,
     awt.CommentCount,
     awt.CreationDate,
     awt.LastActivityDate,
     awt.FavoriteCount,
     awt.UpVotes,
     awt.DownVotes,
     ROW_NUMBER() OVER (PARTITION BY awt.TagName
                      ORDER BY awt.Score DESC, awt.ViewCount DESC, awt.LastActivityDate DESC) AS rn
  FROM ExpandedWithTag awt
),
TopByTag AS (
  SELECT TagName, PostId, Title, OwnerUserId, OwnerName, Score, ViewCount, AnswerCount, CommentCount, CreationDate, LastActivityDate, FavoriteCount, UpVotes, DownVotes
  FROM RankedPerTag
  WHERE rn <= 5
),
RecentActive AS (
  SELECT
     p.Id AS PostId,
     p.Title,
     p.OwnerUserId,
     COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
     p.Score,
     p.ViewCount,
     p.AnswerCount,
     p.CommentCount,
     p.CreationDate,
     p.LastActivityDate,
     p.FavoriteCount,
     COALESCE(va.UpVotes, 0) AS UpVotes,
     COALESCE(va.DownVotes, 0) AS DownVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN VotesAgg va ON va.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days')
    AND p.CommentCount > 0
),
Set1 AS (
  SELECT
     'PopularPerTag' AS SetName,
     0 AS Indicator,
     t.PostId,
     t.Title,
     t.OwnerUserId,
     t.OwnerName,
     t.Score,
     t.ViewCount,
     t.AnswerCount,
     t.CommentCount,
     t.CreationDate,
     t.LastActivityDate,
     t.FavoriteCount,
     t.UpVotes,
     t.DownVotes,
     t.TagName AS TagName,
     CASE WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = t.OwnerUserId AND b.Class = 1) THEN 'Gold' ELSE NULL END AS GoldBadge
  FROM TopByTag t
),
Set2 AS (
  SELECT
     'RecentActive' AS SetName,
     1 AS Indicator,
     pa.PostId,
     pa.Title,
     pa.OwnerUserId,
     pa.OwnerName,
     pa.Score,
     pa.ViewCount,
     pa.AnswerCount,
     pa.CommentCount,
     pa.CreationDate,
     pa.LastActivityDate,
     pa.FavoriteCount,
     pa.UpVotes,
     pa.DownVotes,
     NULL AS TagName,
     CASE WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = pa.OwnerUserId AND b.Class = 1) THEN 'Gold' ELSE NULL END AS GoldBadge
  FROM RecentActive pa
)
SELECT *
FROM Set1
UNION ALL
SELECT *
FROM Set2
ORDER BY SetName, LastActivityDate DESC
LIMIT 200;