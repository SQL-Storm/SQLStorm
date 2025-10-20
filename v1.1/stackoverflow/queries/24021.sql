-- {"query": "24021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2778} 
WITH cte_questions AS (
    SELECT p.Id            AS PostId,
           p.Title,
           p.Score,
           p.ViewCount,
           p.Tags,
           u.Reputation    AS OwnerRep,
           u.DisplayName   AS OwnerDisplayName,
           p.CreationDate,
           COALESCE(
                ( SELECT MIN(ph.CreationDate)
                  FROM PostHistory ph
                 WHERE ph.PostId   = p.Id
                   AND ph.PostHistoryTypeId IN
                        (2,5,6,8,10,12,14,16,18,20,22,24,25,52,53)
                ),
                p.CreationDate
           )                     AS FirstEditDate,
           COALESCE(
                ( SELECT ph.Comment
                  FROM PostHistory ph
                 WHERE ph.PostId   = p.Id
                   AND ph.PostHistoryTypeId = 10
                 ORDER BY ph.CreationDate DESC
                 LIMIT 1
                ),
                'N/A'
           )                      AS LastCloseReason
    FROM Posts p
    LEFT JOIN Users u
           ON p.OwnerUserId = u.Id
   WHERE p.PostTypeId = 1          -- only questions
),
cte_stats AS (
    SELECT q.PostId,
           q.Title,
           q.Score,
           q.ViewCount,
           q.Tags,
           q.OwnerRep,
           q.OwnerDisplayName,
           q.FirstEditDate,
           q.LastCloseReason,
           COUNT(DISTINCT v.Id) AS VoteCount,
           COUNT(DISTINCT c.Id) AS CommentCount,
           COUNT(DISTINCT l.Id) AS LinkCount,
           ( SELECT MAX(p2.ViewCount)
             FROM Posts p2
            WHERE p2.Id = q.PostId
           )                 AS MaxViewSameSeries
    FROM cte_questions q
    LEFT JOIN Votes v
           ON v.PostId = q.PostId
    LEFT JOIN Comments c
           ON c.PostId = q.PostId
    LEFT JOIN PostLinks l
           ON l.PostId = q.PostId OR l.RelatedPostId = q.PostId
   GROUP BY q.PostId, q.Title, q.Score, q.ViewCount, q.Tags,
            q.OwnerRep, q.OwnerDisplayName,
            q.FirstEditDate, q.LastCloseReason
),
cte_ranked AS (
    SELECT s.*,
           RANK() OVER (ORDER BY s.Score DESC, s.VoteCount DESC)      AS GlobalRank,
           NTILE(4) OVER (PARTITION BY s.Tags ORDER BY s.Score DESC)  AS TagQuartile,
           PERCENT_RANK() OVER (ORDER BY s.Score DESC)                AS ScorePercentile
    FROM cte_stats s
),
cte_duplicates AS (
    SELECT DISTINCT pl.PostId AS DuplicateOf
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3          -- duplicate link
)
SELECT r.PostId,
       r.Title,
       r.Score,
       r.VoteCount,
       r.CommentCount,
       r.LinkCount,
       r.OwnerRep,
       r.OwnerDisplayName,
       r.LastCloseReason,
       r.GlobalRank,
       r.TagQuartile,
       r.ScorePercentile,
       CASE
           WHEN r.OwnerRep > 50000 AND r.Score > 30 THEN 'Gold'
           WHEN r.OwnerRep BETWEEN 1000 AND 50000 THEN 'Silver'
           ELSE 'Bronze'
       END                                   AS ReputationRibbon,
       CASE
           WHEN dd.DuplicateOf IS NOT NULL THEN 'Duplicate'
           ELSE 'Original'
       END                                   AS PostStatus,
       r.MaxViewSameSeries
FROM cte_ranked r
LEFT JOIN cte_duplicates dd
       ON dd.DuplicateOf = r.PostId
WHERE r.GlobalRank <= 20
   OR r.CommentCount >= 50
ORDER BY r.GlobalRank, r.CommentCount DESC;