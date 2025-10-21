-- {"query": "43018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 515} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(ph.CreationDate - p.CreationDate) AS AvgEditTime,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > NOW() - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TagPostCount,
        AVG(p.ViewCount) AS AvgTagViewCount
    FROM Tags t
    JOIN Posts p ON t.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), ''><'')::int[])
    WHERE p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
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
    SELECT *
    FROM TopTags
    ORDER BY TagPostCount DESC
    LIMIT 3
) tt
WHERE ua.TotalScore > 100
ORDER BY ua.TotalScore DESC, tt.TagPostCount DESC;
