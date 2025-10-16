-- {"query": "24094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3112} 
WITH top_score AS (
    SELECT Id, Title, Score, ViewCount, Tags
    FROM Posts
    WHERE PostTypeId = 1
    ORDER BY Score DESC
    LIMIT 10
),
top_view AS (
    SELECT Id, Title, Score, ViewCount, Tags
    FROM Posts
    WHERE PostTypeId = 1
    ORDER BY ViewCount DESC
    LIMIT 10
),
combined AS (
    SELECT * FROM top_score
    UNION ALL
    SELECT * FROM top_view
),
high_rep_comments AS (
    SELECT P.Id AS PostId,
           COUNT(*) AS HighRepCommentCount
    FROM Posts P
    JOIN Comments C ON C.PostId = P.Id
    JOIN Users U ON U.Id = C.UserId
    WHERE U.Reputation > 20000
    GROUP BY P.Id
),
duplicate_counts AS (
    SELECT PL.PostId,
           COUNT(*) AS DuplicateCount
    FROM PostLinks PL
    WHERE PL.LinkTypeId = 3
    GROUP BY PL.PostId
),
first_edit AS (
    SELECT PH.PostId,
           MIN(PH.CreationDate) AS FirstEditDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4,5,6)
    GROUP BY PH.PostId
)
SELECT
    c.Id                      AS PostId,
    c.Title,
    c.Score,
    c.ViewCount,
    COALESCE(h.HighRepCommentCount,0)   AS HighRepCommentCount,
    COALESCE(d.DuplicateCount,0)        AS DuplicateCount,
    COALESCE(f.FirstEditDate, TIMESTAMP '1970-01-01') AS FirstEditDate,
    c.Tags,
    ROW_NUMBER() OVER (ORDER BY c.Score DESC, c.ViewCount DESC) AS GlobalRank
FROM combined c
LEFT JOIN high_rep_comments h ON h.PostId = c.Id
LEFT JOIN duplicate_counts d ON d.PostId = c.Id
LEFT JOIN first_edit f ON f.PostId = c.Id
ORDER BY GlobalRank;