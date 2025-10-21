-- {"query": "9096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3604} 

WITH RecentQ AS (
    SELECT 
        p.Id                     AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        cardinality(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS TagCount,
        ROW_NUMBER() OVER (
            PARTITION BY date_trunc('month', p.CreationDate)
            ORDER BY p.Score DESC, p.ViewCount DESC
        ) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1
), 
AnswerInfo AS (
    SELECT 
        a.ParentId                 AS QuestionId,
        COUNT(*)                   AS TotalAnswers,
        AVG(a.Score)::numeric(10,2) AS AvgScore,
        MAX(a.Score)               AS MaxScore,
        (
            SELECT body 
            FROM Posts p2 
            WHERE p2.Id = a.Id 
            ORDER BY p2.Score DESC 
            LIMIT 1
        )                          AS BestAnswer
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
), 
UserBadge AS (
    SELECT 
        u.Id              AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Users u
    LEFT JOIN Badges b 
      ON b.UserId = u.Id 
     AND b.Date > now() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
), 
TopUsers AS (
    SELECT 
        ub.*,
        (ub.Gold*3 + ub.Silver*2 + ub.Bronze) AS BadgeScore,
        EXTRACT(month FROM age(now(), ub.CreationDate)) AS ActiveMonths
    FROM UserBadge ub
    WHERE ub.Reputation > (SELECT AVG(Reputation) FROM Users)
), 
Combined AS (
    SELECT
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        rq.TagCount,
        ai.TotalAnswers,
        ai.AvgScore,
        ai.MaxScore,
        ai.BestAnswer,
        tu.DisplayName,
        tu.Reputation    AS UserRep,
        tu.BadgeScore
    FROM RecentQ rq
    LEFT JOIN AnswerInfo ai 
      ON ai.QuestionId = rq.QuestionId
    LEFT JOIN TopUsers tu 
      ON tu.UserId = rq.OwnerUserId
    WHERE rq.RowNum <= 5
)
SELECT
    c.QuestionId,
    LEFT(c.Title,50) || '...'                                    AS Snippet,
    c.DisplayName                                               AS Author,
    c.UserRep,
    COALESCE(c.BadgeScore,0)                                     AS BadgeScore,
    c.Score,
    c.ViewCount,
    c.TotalAnswers,
    c.AvgScore,
    c.MaxScore,
    LEFT(REGEXP_REPLACE(COALESCE(c.BestAnswer,''), E'<[^>]+>','','g'),100) AS AnswerPreview,
    array_to_string(
      string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><'),
      ','
    )                                                           AS TagList
FROM Combined c
LEFT JOIN Posts p 
  ON p.Id = c.QuestionId
WHERE c.Score > (
    SELECT percentile_cont(0.5) 
      WITHIN GROUP (ORDER BY Score) 
    FROM Posts 
    WHERE PostTypeId=1
)
UNION ALL
SELECT
    NULL,NULL,NULL,NULL,NULL,
    NULL,
    SUM(TotalAnswers),
    AVG(AvgScore),
    MAX(MaxScore),
    NULL,
    NULL
FROM Combined
ORDER BY BadgeScore DESC, TotalAnswers DESC;
