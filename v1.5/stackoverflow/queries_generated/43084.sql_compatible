WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, SUM(p.Score) DESC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.ViewCount) AS AvgViewCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
RecentEdits AS (
    SELECT 
        ph.UserId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY ph.UserId
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalScore,
    re.EditCount,
    re.LastEditDate,
    tt.TagName AS MostCommonTag,
    tt.QuestionCount,
    tt.AvgViewCount
FROM UserActivity ua
LEFT JOIN RecentEdits re ON ua.UserId = re.UserId
LEFT JOIN LATERAL (
    SELECT t.TagName, t.QuestionCount, t.AvgViewCount
    FROM TopTags t
    WHERE ua.TotalQuestions > 0
    ORDER BY t.TagRank
    LIMIT 1
) tt ON TRUE
WHERE ua.UserRank <= 100
ORDER BY ua.UserRank ASC, re.EditCount DESC, tt.QuestionCount DESC;