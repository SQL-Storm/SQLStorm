-- {"query": "13063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 897} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        DENSE_RANK() OVER (ORDER BY SUM(p.Score) DESC) AS RankByScore
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        u.Id
),
TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        COUNT(a.Id) AS AnswerCount,
        STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
    FROM 
        Posts p
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN 
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id
    HAVING 
        COUNT(a.Id) > 0
),
FinalResultSet AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.TotalPosts,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.AvgScore,
        ua.RankByScore,
        tq.QuestionId,
        tq.Title,
        tq.Score AS QuestionScore,
        tq.AnswerCount,
        tq.Tags
    FROM 
        UserActivity ua
    CROSS APPLY (
        SELECT TOP 5 *
        FROM 
            TopQuestions tq
        WHERE 
            tq.Tags LIKE CONCAT('%', SUBSTRING((SELECT TOP 1 ph.Text FROM PostHistory ph WHERE ph.PostId = tq.QuestionId AND ph.PostHistoryTypeId = 6 ORDER BY ph.CreationDate DESC LIMIT 1), 2, LENGTH((SELECT TOP 1 ph.Text FROM PostHistory ph WHERE ph.PostId = tq.QuestionId AND ph.PostHistoryTypeId = 6 ORDER BY ph.CreationDate DESC LIMIT 1)) - 2), '%')
        ORDER BY 
            tq.Score DESC, tq.AnswerCount DESC
    ) tq
    WHERE 
        ua.TotalPosts > 10
)
SELECT 
    frs.UserId,
    frs.DisplayName,
    frs.TotalPosts,
    frs.TotalQuestions,
    frs.TotalAnswers,
    frs.AvgScore,
    frs.RankByScore,
    frs.QuestionId,
    frs.Title,
    frs.QuestionScore,
    frs.AnswerCount,
    frs.Tags,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = frs.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = frs.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = frs.UserId AND b.Class = 3) AS BronzeBadges
FROM 
    FinalResultSet frs
ORDER BY 
    frs.RankByScore, frs.TotalQuestions DESC
LIMIT 100;
