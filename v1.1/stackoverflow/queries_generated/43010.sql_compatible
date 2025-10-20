WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore
    FROM 
        Tags t
    JOIN 
        Posts p ON EXISTS (
            SELECT 1
            FROM (
                -- split tags string like '<tag1><tag2>' into rows
                SELECT TRIM(both '<>' FROM part) AS tag
                FROM (
                    SELECT regexp_split_to_table(COALESCE(p.Tags, ''), '><') AS part
                ) s
            ) tagparts
            WHERE tagparts.tag = t.TagName
        )
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(p.Id) > 10
    ORDER BY 
        PostCount DESC
    LIMIT 
        10
)
SELECT
    ua.UserId,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.BadgeCount,
    ua.PostHistoryCount,
    tt.TagName,
    tt.PostCount,
    tt.AvgScore
FROM 
    UserActivity ua
CROSS JOIN 
    TopTags tt
GROUP BY
    ua.UserId,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.BadgeCount,
    ua.PostHistoryCount,
    tt.TagName,
    tt.PostCount,
    tt.AvgScore
ORDER BY 
    ua.TotalScore DESC, tt.PostCount DESC;