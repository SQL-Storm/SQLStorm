-- {"query": "15056.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 133095, "output_tokens": 39276} 
WITH QuestionRanking AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount,
        p.AnswerCount,
        DENSE_RANK() OVER (
            PARTITION BY 
                EXTRACT(YEAR FROM p.CreationDate), 
                CASE 
                    WHEN LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1 > 3 THEN 'Complex'
                    ELSE 'Simple'
                END 
            ORDER BY 
                p.Score * COALESCE(p.ViewCount, 1) DESC
        ) as YearlyTagComplexityRank,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentTotal,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END as IsClosed
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > '2015-01-01'
        AND p.ViewCount > 100
),
UserContribution AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        SUM(p.Score) as TotalQuestionScore,
        AVG(p.AnswerCount) as AvgAnswersPerQuestion
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    qr.Title,
    qr.Score,
    qr.ViewCount,
    qr.YearlyTagComplexityRank,
    uc.DisplayName,
    uc.QuestionCount,
    qr.CommentTotal,
    qr.IsClosed,
    ROUND(
        qr.Score * LOG(qr.ViewCount + 1) * 
        (1.0 / (qr.YearlyTagComplexityRank + 1)) * 
        (CASE WHEN qr.IsClosed = 0 THEN 1.2 ELSE 0.8 END),
        2
    ) as ComplexityScore
FROM 
    QuestionRanking qr
JOIN 
    UserContribution uc ON EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.Id = qr.Id AND p.OwnerUserId = uc.UserId
    )
WHERE 
    qr.YearlyTagComplexityRank <= 10
    AND uc.QuestionCount > 5
    AND qr.CommentTotal > 0
ORDER BY 
    ComplexityScore DESC
LIMIT 100;