-- {"query": "43095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 562} 

WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        RANK() OVER (ORDER BY u.Reputation DESC) as UserRank
    FROM Users u
    WHERE u.Reputation > 1000
),
UserQuestions AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) as TotalQuestions,
        SUM(p.Score) as TotalScore,
        AVG(p.ViewCount) as AvgViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.OwnerUserId
),
QuestionAnswers AS (
    SELECT 
        p.ParentId as QuestionId,
        COUNT(p.Id) as AnswerCount,
        MAX(p.Score) as BestAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
FinalData AS (
    SELECT 
        tu.Id as UserId,
        tu.DisplayName,
        tu.Reputation,
        uq.TotalQuestions,
        uq.TotalScore,
        uq.AvgViewCount,
        qa.AnswerCount,
        qa.BestAnswerScore
    FROM TopUsers tu
    JOIN UserQuestions uq ON tu.Id = uq.OwnerUserId
    LEFT JOIN QuestionAnswers qa ON uq.OwnerUserId = qa.QuestionId
    WHERE tu.UserRank <= 100
)
SELECT 
    fd.UserId,
    fd.DisplayName,
    fd.Reputation,
    fd.TotalQuestions,
    fd.TotalScore,
    fd.AvgViewCount,
    COALESCE(fd.AnswerCount, 0) as AnswerCount,
    COALESCE(fd.BestAnswerScore, 0) as BestAnswerScore,
    b.Name as HighestBadge,
    b.Date as BadgeEarnedDate
FROM FinalData fd
LEFT JOIN (
    SELECT 
        b.UserId,
        b.Name,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) as BadgeRank
    FROM Badges b
) b ON fd.UserId = b.UserId AND b.BadgeRank = 1
ORDER BY fd.Reputation DESC, fd.TotalScore DESC;
