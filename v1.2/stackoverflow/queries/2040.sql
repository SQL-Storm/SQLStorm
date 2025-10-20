WITH RECURSIVE RecursiveConnexions AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           1 AS depth
      FROM PostLinks pl
     WHERE pl.PostId IN (
           SELECT Id
             FROM Posts
            ORDER BY viewcount DESC
            LIMIT 100
           )
    UNION ALL
    SELECT rc.RelatedPostId AS PostId,
           pl.RelatedPostId,
           rc.depth + 1
      FROM RecursiveConnexions rc
      JOIN PostLinks pl
        ON pl.PostId = rc.RelatedPostId
)
SELECT rc.PostId,
       rc.RelatedPostId,
       rc.depth
  FROM RecursiveConnexions rc;