WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))) AS AvgEditTime,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS TagPostCount,
        AVG(p.ViewCount) AS AvgTagViewCount
    FROM Tags t
    JOIN Posts p ON EXISTS (
        SELECT 1
        FROM (
            SELECT trim(both '<>' FROM val) AS tag
            FROM regexp_split_to_table(
                CASE 
                    WHEN p.Tags IS NULL THEN '' 
                    WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2)
                    ELSE p.Tags
                END,
                '><'
            ) AS vals(val)
        ) v
        WHERE v.tag = t.TagName
    )
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 10
    ORDER BY TagPostCount DESC
    LIMIT 10
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.AvgEditTime,
    ua.BadgeCount,
    tt.TagName,
    tt.TagPostCount,
    tt.AvgTagViewCount
FROM UserActivity ua
CROSS JOIN LATERAL (
    SELECT TagName, TagPostCount, AvgTagViewCount
    FROM TopTags
    ORDER BY TagPostCount DESC
    LIMIT 3
) tt
WHERE ua.TotalScore > 100
ORDER BY ua.TotalScore DESC, tt.TagPostCount DESC;