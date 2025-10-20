WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgeScore,
        COUNT(v.Id) AS UpvotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalQuestions,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.ViewCount) AS MaxViews
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
AnswerStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(CASE WHEN p.Id = pp.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Posts p
    LEFT JOIN Posts pp ON p.Id = pp.AcceptedAnswerId
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
TagUsage AS (
    -- portable tag splitting using a recursive CTE
    SELECT
        base.OwnerUserId,
        pu.tag AS TagName,
        COUNT(*) AS TagPosts
    FROM (
        SELECT
            p.OwnerUserId,
            CASE
                WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
                WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2)
                ELSE p.Tags
            END AS tags_str
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) base
    JOIN LATERAL (
        WITH RECURSIVE split(idx, rest, tag) AS (
            SELECT CAST(1 AS integer),
                   CAST(base.tags_str AS text),
                   CAST(NULL AS text)
            UNION ALL
            SELECT
                idx + 1,
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                    ELSE ''
                END,
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
                    ELSE rest
                END
            FROM split
            WHERE rest <> ''
        )
        SELECT idx, TRIM(tag) AS tag
        FROM split
        WHERE tag IS NOT NULL AND tag <> ''
    ) pu(idx, tag)
    ON TRUE
    JOIN Tags t ON t.TagName = pu.tag
    GROUP BY base.OwnerUserId, pu.tag
),
TopTag AS (
    SELECT 
        OwnerUserId,
        TagName,
        TagPosts,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagPosts DESC) AS rn
    FROM TagUsage
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.TotalPostScore,
    us.TotalViews,
    us.TotalBadges,
    us.BadgeScore,
    us.UpvotesReceived,
    qs.TotalQuestions,
    qs.AvgQuestionScore,
    qs.MaxViews,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.AcceptedAnswers,
    tt.TagName AS TopTag,
    (us.Reputation * 0.1 + us.TotalPostScore * 0.2 + us.UpvotesReceived * 0.3 + us.BadgeScore * 0.4) AS CompositeScore
FROM UserStats us
LEFT JOIN QuestionStats qs ON us.UserId = qs.OwnerUserId
LEFT JOIN AnswerStats ans ON us.UserId = ans.OwnerUserId
LEFT JOIN TopTag tt ON us.UserId = tt.OwnerUserId AND tt.rn = 1
WHERE us.TotalPosts > 0
ORDER BY CompositeScore DESC, us.TotalPosts DESC
LIMIT 100;