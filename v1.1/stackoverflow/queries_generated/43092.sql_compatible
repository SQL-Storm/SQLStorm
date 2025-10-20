WITH TopAnswerers AS (
    SELECT 
        u.Id,
        u.DisplayName, 
        u.Reputation, 
        COUNT(p.Id) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgAnswerScore,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC, SUM(p.Score) DESC) AS AnswererRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 2 
        AND p.CreationDate >= DATE '2024-10-01' - INTERVAL '1' YEAR
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id AS QuestionId, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.Tags,
        u.Id AS QuestionOwnerId,
        u.DisplayName AS QuestionOwner,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= DATE '2024-10-01' - INTERVAL '1' YEAR
    ORDER BY 
        p.Score DESC, p.ViewCount DESC
    LIMIT 10
)
SELECT 
    ta.DisplayName,
    ta.Reputation,
    ta.TotalAnswers,
    ta.TotalScore,
    ta.AvgAnswerScore,
    tq.QuestionId,
    tq.Title,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tq.Tags,
    tq.CommentCount,
    tq.GoldBadges
FROM 
    TopAnswerers ta
JOIN 
    Posts p ON ta.Id = p.OwnerUserId
JOIN 
    TopQuestions tq ON p.ParentId = tq.QuestionId
WHERE 
    ta.AnswererRank <= 10
ORDER BY 
    ta.AnswererRank, tq.Score DESC, tq.ViewCount DESC;