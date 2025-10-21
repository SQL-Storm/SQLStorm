-- {"query": "24045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3882} 

WITH
    /* Duplicate questions pulled via PostLinks */
    Dup AS (
        SELECT pl.PostId AS Id, 'Duplicate' AS Source
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
    ),

    /* Base set of original questions */
    Q AS (
        SELECT p.Id,
               p.Title,
               p.Score,
               p.ViewCount,
               p.CreationDate,
               p.Tags,
               'Question' AS Source
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),

    /* Combine original and duplicate rows */
    Combined AS (
        SELECT * FROM Q
        UNION ALL
        SELECT d.Id,
               p.Title,
               p.Score,
               p.ViewCount,
               p.CreationDate,
               p.Tags,
               d.Source
        FROM Dup d
        JOIN Posts p ON p.Id = d.Id
    ),

    /* Top 100 rows by score, breaking ties by view count  */
    TopCombined AS (
        SELECT * FROM Combined
        ORDER BY Score DESC, ViewCount DESC
        FETCH FIRST 100 ROWS ONLY
    ),

    /* Comment counts per post */
    Comm AS (
        SELECT c.PostId,
               COUNT(*) AS CommentCount
        FROM Comments c
        WHERE c.PostId IN (SELECT Id FROM TopCombined)
        GROUP BY c.PostId
    ),

    /* Vote statistics per post */
    VotesStat AS (
        SELECT v.PostId,
               SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)        AS UpVotes,
               SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)        AS DownVotes,
               SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                        WHEN v.VoteTypeId = 3 THEN -1
                        ELSE 0 END)                                  AS NetScore
        FROM Votes v
        WHERE v.PostId IN (SELECT Id FROM TopCombined)
        GROUP BY v.PostId
    ),

    /* Count of accepted answers for posts that have one */
    Accepted AS (
        SELECT p.Id,
               (SELECT COUNT(*)
                FROM Posts a
                WHERE a.ParentId = p.Id
                  AND a.Score > 0)                                     AS AcceptedAnswerCount
        FROM Posts p
        WHERE p.Id IN (SELECT Id FROM TopCombined)
          AND p.AcceptedAnswerId IS NOT NULL
    ),

    /* Window function to rank per first tag seen in the Tags string */
    TagRank AS (
        SELECT tc.Id,
               tc.Title,
               tc.Score,
               tc.ViewCount,
               tc.CreationDate,
               tc.Tags,
               substring(tc.Tags from '<([^>]+)>')                     AS FirstTag,
               ROW_NUMBER() OVER (PARTITION BY substring(tc.Tags from '<([^>]+)>')
                    ORDER BY tc.Score DESC, tc.ViewCount DESC)          AS TagRank
        FROM TopCombined tc
    )
SELECT tr.Id,
       tr.FirstTag,
       tr.TagRank,
       tr.Score,
       tr.ViewCount,
       COALESCE(cs.CommentCount, 0)       AS CommentCount,
       vs.UpVotes,
       vs.DownVotes,
       vs.NetScore,
       COALESCE(a.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
       tr.Source,
       CASE
           WHEN vs.NetScore > 100 AND tr.ViewCount > 20000 THEN 'Star'
           WHEN vs.NetScore > 0   AND tr.ViewCount > 5000  THEN 'Hot'
           ELSE 'Regular'
       END                                               AS Ranking
FROM TagRank tr
LEFT JOIN Comm   cs ON cs.PostId = tr.Id
LEFT JOIN VotesStat vs ON vs.PostId = tr.Id
LEFT JOIN Accepted a ON a.Id = tr.Id
WHERE tr.TagRank <= 3
ORDER BY vs.NetScore DESC, tr.Score DESC;
