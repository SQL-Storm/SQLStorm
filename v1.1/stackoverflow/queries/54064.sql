-- {"query": "54064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2099} 
WITH
  q AS (
    SELECT p.Id AS qid, p.OwnerUserId AS uid, p.CreationDate,
           p.Score, p.ViewCount, p.AnswerCount,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END),0) AS upvotes,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END),0) AS downvotes,
           COALESCE(COUNT(ph.Id),0) AS edit_cnt,
           COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END),0) AS body_edit,
           COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 END),0) AS tag_edit,
           COALESCE(COUNT(DISTINCT pl.RelatedPostId),0) AS dup_cnt
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2023-01-01'
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount
  ),
  u AS (
    SELECT u.Id uid, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
  )
SELECT q.*, u.DisplayName, u.Reputation, u.RepRank,
       DENSE_RANK() OVER (ORDER BY q.edit_cnt DESC) AS EditRank,
       RANK() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS HotRank
FROM q
JOIN u ON u.uid = q.uid
WHERE u.Reputation > 500
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 100;