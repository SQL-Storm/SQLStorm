-- {"query": "3927.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1973} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id)                                          AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)                 AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)                 AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)                 AS BronzeBadges,
        COALESCE(SUM(p.Score),0)                                      AS TotalPostScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END),0) AS TotalQuestionViews,
        MAX(p.CreationDate)                                           AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

RankedUsers AS (
    SELECT 
        *, 
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, BadgeCount DESC) AS RepRank,
        RANK()       OVER (ORDER BY TotalPostScore DESC)                AS ScoreRank
    FROM UserStats
),

TagActivity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id)                     AS QuestionCount,
        SUM(p.Score)                             AS ScoreSum,
        CAST(AVG(p.ViewCount) AS NUMERIC(10,2)) AS AvgViews,
        MAX(p.CreationDate)                      AS LatestQuestion
    FROM Tags t
    JOIN Posts p 
        ON p.PostTypeId = 1
       AND p.Tags LIKE CONCAT('%', t.TagName, '%')
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
),

CloseReasonStats AS (
    SELECT 
        CAST(ch.Comment AS INT) AS CloseReasonId,
        COUNT(*)                AS ClosedCount,
        MIN(ch.CreationDate)    AS FirstClosed,
        MAX(ch.CreationDate)    AS LastClosed
    FROM PostHistory ch
    WHERE ch.PostHistoryTypeId = 10
      AND ch.Comment ~ '^\d+$'
    GROUP BY CAST(ch.Comment AS INT)
),

TopActiveUsers AS (
    SELECT 
        ru.Id,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPostScore,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = ru.Id 
           AND p.PostTypeId = 2 
           AND p.Score > 0)                AS PositiveAnswerCount,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.UserId = ru.Id 
           AND c.Score >= 0)                AS PositiveCommentCount
    FROM RankedUsers ru
    WHERE ru.RepRank <= 100
),

Combined AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.TotalPostScore,
        u.TotalQuestionViews,
        COALESCE(t.TagName, '<no tag>')                         AS TopTag,
        cr.CloseReasonId,
        CASE 
            WHEN u.Reputation > 20000 THEN 'Veteran'
            WHEN u.Reputation BETWEEN 10000 AND 20000 THEN 'Experienced'
            WHEN u.Reputation BETWEEN 5000  AND 9999  THEN 'Intermediate'
            ELSE 'Newbie'
        END                                                    AS ReputationBand,
        CASE 
            WHEN u.TotalPostScore > 0 THEN u.TotalPostScore / NULLIF(u.Reputation,0)
            ELSE NULL
        END                                                    AS ScorePerRep
    FROM TopActiveUsers u
    LEFT JOIN LATERAL (
        SELECT t.TagName
        FROM TagActivity t
        ORDER BY t.ScoreSum DESC
        LIMIT 1
    ) t ON TRUE
    LEFT JOIN LATERAL (
        SELECT cr.CloseReasonId
        FROM CloseReasonStats cr
        ORDER BY cr.ClosedCount DESC
        LIMIT 1
    ) cr ON TRUE
)

SELECT *
FROM Combined
WHERE ReputationBand IN ('Veteran','Experienced')
  AND (ScorePerRep IS NULL OR ScorePerRep > 0.5)
ORDER BY Reputation DESC, TotalPostScore DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY

UNION ALL

SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE EXISTS (SELECT 1 FROM (SELECT 1) AS dummy);
