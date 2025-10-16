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
        p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY 
        u.Id,
        u.DisplayName
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
        Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id,
        p.Title,
        p.Score,
        p.Tags
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
    JOIN LATERAL (
        SELECT
            tq2.QuestionId,
            tq2.Title,
            tq2.Score,
            tq2.AnswerCount,
            tq2.Tags
        FROM 
            TopQuestions tq2
        WHERE 
            -- attempt to match TopQuestions tags against latest PostHistory text for that question
            EXISTS (
                SELECT 1
                FROM PostHistory ph
                WHERE ph.PostId = tq2.QuestionId
                  AND ph.PostHistoryTypeId = 6
                ORDER BY ph.CreationDate DESC
                LIMIT 1
            )
            AND (
                -- build a substring of the latest PostHistory text without first and last char, if available
                -- compare using LIKE; use COALESCE guards
                tq2.Tags LIKE '%' || COALESCE(
                    SUBSTR(
                        (SELECT ph.Text FROM PostHistory ph WHERE ph.PostId = tq2.QuestionId AND ph.PostHistoryTypeId = 6 ORDER BY ph.CreationDate DESC LIMIT 1),
                        2,
                        (LENGTH((SELECT ph.Text FROM PostHistory ph WHERE ph.PostId = tq2.QuestionId AND ph.PostHistoryTypeId = 6 ORDER BY ph.CreationDate DESC LIMIT 1)) - 2)
                    ),
                    ''
                ) || '%'
            )
        ORDER BY 
            tq2.Score DESC,
            tq2.AnswerCount DESC
        LIMIT 5
    ) tq ON true
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
    frs.RankByScore,
    frs.TotalQuestions DESC
LIMIT 100;