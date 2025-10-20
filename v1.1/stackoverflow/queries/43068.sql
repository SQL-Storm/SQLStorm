WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.ViewCount) AS AvgPostViewCount,
        COUNT(DISTINCT ph.Id) AS EditsCount,
        COUNT(DISTINCT b.Id) AS BadgesCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
    GROUP BY 
        u.Id,
        u.DisplayName,
        u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS QuestionsCount,
        AVG(p.AnswerCount) AS AvgAnswers,
        AVG(p.ViewCount) AS AvgViews
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
    ORDER BY 
        QuestionsCount DESC, AvgAnswers DESC
    LIMIT 10
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.PostsCount,
    ua.TotalPostScore,
    ua.AvgPostViewCount,
    ua.EditsCount,
    ua.BadgesCount,
    tt.TagName,
    tt.QuestionsCount,
    tt.AvgAnswers,
    tt.AvgViews
FROM 
    UserActivity ua
CROSS JOIN 
    TopTags tt
ORDER BY 
    ua.Reputation DESC, ua.PostsCount DESC, tt.QuestionsCount DESC;