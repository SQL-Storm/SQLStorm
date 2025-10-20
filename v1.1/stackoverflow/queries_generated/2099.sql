-- {"query": "2099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 597} 

WITH RankedAnswers AS (
    SELECT 
        p.Id AS QuestionId, 
        a.Id AS AnswerId, 
        a.Score AS AnswerScore, 
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM 
        Posts p
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId 
    WHERE 
        p.PostTypeId = 1 AND a.PostTypeId = 2
),
UserBadgeCounts AS (
    SELECT 
        b.UserId, 
        COUNT(DISTINCT b.Id) AS TotalBadges, 
        COUNT(DISTINCT CASE WHEN TagBased = 1 THEN b.Id END) AS TagBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
QuestionCommentAverages AS (
    SELECT 
        c.PostId, 
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    INNER JOIN 
        Posts p ON c.PostId = p.Id
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        c.PostId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(ubc.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubc.TagBadges, 0) AS TagBadges,
    pa.AnswerCount,
    COALESCE(qc.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(r.FirstAnswerScore, 0) AS FirstAnswerScore,
    COALESCE(r.SecondAnswerScore, 0) AS SecondAnswerScore
FROM 
    Users u
LEFT JOIN 
    UserBadgeCounts ubc ON u.Id = ubc.UserId
LEFT JOIN (
    SELECT 
        p.OwnerUserId, 
        COUNT(DISTINCT p.Id) AS AnswerCount
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2
    GROUP BY 
        p.OwnerUserId
) pa ON u.Id = pa.OwnerUserId
LEFT JOIN 
    QuestionCommentAverages qc ON u.Id = qc.PostId
LEFT JOIN (
    SELECT
        ra.QuestionId,
        MAX(CASE WHEN ra.AnswerRank = 1 THEN ra.AnswerScore ELSE NULL END) AS FirstAnswerScore,
        MAX(CASE WHEN ra.AnswerRank = 2 THEN ra.AnswerScore ELSE NULL END) AS SecondAnswerScore
    FROM 
        RankedAnswers ra
    GROUP BY 
        ra.QuestionId
) r ON qc.PostId = r.QuestionId
WHERE 
    u.Reputation > 1000
AND 
    (ubc.TotalBadges > 0 OR pa.AnswerCount > 5)
ORDER BY 
    u.Reputation DESC, u.DisplayName;
