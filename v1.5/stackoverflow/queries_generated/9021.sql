-- {"query": "9021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 6559} 

WITH
TagSplit AS (
    SELECT p.Id     AS PostId,
           t        AS Tag
    FROM Posts p
    LEFT JOIN LATERAL unnest(
        string_to_array(
            substring(p.Tags FROM 2 FOR length(p.Tags) - 2)
          , '><'
        )
    ) AS t ON TRUE
    WHERE p.PostTypeId = 1
      AND p.Tags       IS NOT NULL
),
BadgeCounts AS (
    SELECT b.UserId,
           COUNT(*)                                  AS BadgeCount,
           SUM(CASE b.Class WHEN 1 THEN 100
                             WHEN 2 THEN  50
                             ELSE       10 END)       AS BadgeScore
    FROM Badges b
    GROUP BY b.UserId
),
CommentCounts AS (
    SELECT COALESCE(c.UserId, -1)               AS UserId,
           COUNT(*) FILTER(WHERE c.Score >  0)  AS GoodComments,
           COUNT(*) FILTER(WHERE c.Score <= 0
                         OR c.Score IS NULL)     AS OtherComments
    FROM Comments c
    GROUP BY c.UserId
),
TopAnswerers AS (
    SELECT p.OwnerUserId                         AS UserId,
           COUNT(*)                              AS AnswerCount,
           AVG(p.Score)                          AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) > 10
),
FinalStats AS (
    SELECT u.Id                                        AS UserId,
           u.DisplayName,
           COALESCE(bc.BadgeCount,   0)                AS BadgeCount,
           COALESCE(cc.GoodComments,  0)                AS GoodComments,
           COALESCE(ta.AnswerCount,   0)                AS AnswerCount,
           COALESCE(ta.AvgAnswerScore,0)                AS AvgAnswerScore,
           COUNT(DISTINCT ts.Tag)                      AS TagDiversity,
           MAX(
             (SELECT COUNT(*) 
              FROM Votes v 
              WHERE v.PostId    = p.Id
                AND v.VoteTypeId = 2)
           )                                           AS MaxUpVotesReceived,
           ROW_NUMBER() OVER (
             ORDER BY COALESCE(bc.BadgeCount,0) DESC,
                      COALESCE(ta.AvgAnswerScore,0) DESC,
                      u.Reputation DESC
           )                                           AS GlobalRank
    FROM Users u
    LEFT JOIN BadgeCounts   bc ON bc.UserId = u.Id
    LEFT JOIN CommentCounts cc ON cc.UserId = u.Id
    LEFT JOIN TopAnswerers  ta ON ta.UserId = u.Id
    LEFT JOIN Posts         p  ON p.OwnerUserId = u.Id
                            AND p.PostTypeId   = 1
                            AND p.Score        >  0
    LEFT JOIN TagSplit      ts ON ts.PostId      = p.Id
    WHERE u.CreationDate < CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, bc.BadgeCount, cc.GoodComments, ta.AnswerCount, ta.AvgAnswerScore, u.Reputation
)
SELECT * FROM FinalStats

UNION

SELECT u.Id,
       u.DisplayName,
       0       AS BadgeCount,
       0       AS GoodComments,
       0       AS AnswerCount,
       0.0     AS AvgAnswerScore,
       0       AS TagDiversity,
       0       AS MaxUpVotesReceived,
       NULL    AS GlobalRank
FROM Users u
WHERE u.LastAccessDate < CURRENT_TIMESTAMP - INTERVAL '5 years'

EXCEPT

SELECT v.UserId,
       u2.DisplayName,
       SUM(v.BountyAmount)::int AS BadgeCount,
       0                         AS GoodComments,
       0                         AS AnswerCount,
       0.0                       AS AvgAnswerScore,
       0                         AS TagDiversity,
       0                         AS MaxUpVotesReceived,
       0                         AS GlobalRank
FROM Votes v
JOIN Users u2 ON u2.Id = v.UserId
WHERE v.VoteTypeId = 8
GROUP BY v.UserId, u2.DisplayName

INTERSECT

SELECT sub.Id,
       sub.DisplayName,
       (sub.Views / NULLIF(sub.AnswerCount, 0))::numeric AS BadgeCount,
       0                                              AS GoodComments,
       0                                              AS AnswerCount,
       0.0                                            AS AvgAnswerScore,
       0                                              AS TagDiversity,
       0                                              AS MaxUpVotesReceived,
       0                                              AS GlobalRank
FROM (
    SELECT u3.Id,
           u3.DisplayName,
           u3.Views,
           COUNT(p3.Id) AS AnswerCount
    FROM Users u3
    LEFT JOIN Posts p3 ON p3.OwnerUserId = u3.Id
                      AND p3.PostTypeId   = 2
    GROUP BY u3.Id, u3.DisplayName, u3.Views
) AS sub;
