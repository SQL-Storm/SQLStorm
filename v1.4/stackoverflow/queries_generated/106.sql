-- {"query": "106.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2046} 
WITH
RecentQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
OwnerInfo AS (
  SELECT
    rq.Id,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.LastActivityDate,
    COALESCE(u.DisplayName, 'Unknown') AS OwnerName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = rq.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = rq.Id) AS LastVoteDate,
    (SELECT STRING_AGG(vt.Name, ',') FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.PostId = rq.Id) AS VoteTypes
  FROM RecentQuestions rq
  LEFT JOIN Users u ON rq.OwnerUserId = u.Id
),
RankedPosts AS (
  SELECT
    oi.*,
    ROW_NUMBER() OVER (
      ORDER BY
        COALESCE(oi.LastActivityDate, oi.CreationDate) DESC NULLS LAST,
        oi.Score DESC
    ) AS rn
  FROM OwnerInfo oi
)
SELECT
  rn,
  Id,
  Title,
  OwnerName,
  Score,
  ViewCount,
  LastActivityDate,
  CommentCount,
  AnswerCount,
  LastVoteDate,
  VoteTypes
FROM RankedPosts
WHERE rn <= 100
ORDER BY LastActivityDate DESC NULLS LAST, Score DESC;