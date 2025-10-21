WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(COALESCE(p.Score,0)) AS TotalScore,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE 
        u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
    HAVING SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 50
)
, UserAcceptedAnswers AS (
    SELECT
        u.UserId,
        COUNT(p.Id) AS AcceptedAnswers
    FROM
        TopUsers u
        JOIN Posts p ON p.OwnerUserId = u.UserId AND p.PostTypeId = 2
        JOIN Posts q ON q.AcceptedAnswerId = p.Id
        LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
    GROUP BY u.UserId
)
, TagPerformance AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TaggedPosts,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes
    FROM
        Tags t
        JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
        LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE
        t.Count > 500
    GROUP BY t.TagName
)
SELECT
    tu.DisplayName,
    tu.AnswerCount,
    tu.QuestionCount,
    tu.TotalScore,
    tu.BadgeCount,
    COALESCE(ua.AcceptedAnswers, 0) AS AcceptedAnswers,
    COUNT(DISTINCT c.Id) AS RecentComments,
    tp.TagName AS MostPopularTag,
    tp.TaggedPosts AS PostsWithTag,
    tp.AvgScore AS AvgScoreOnTag
FROM
    TopUsers tu
    LEFT JOIN UserAcceptedAnswers ua ON ua.UserId = tu.UserId
    LEFT JOIN Comments c ON c.UserId = tu.UserId AND c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            t.TagName,
            COUNT(*) AS TaggedPosts,
            AVG(p.Score) AS AvgScore
        FROM
            Posts p
            CROSS JOIN LATERAL (
                SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
            ) t
        WHERE
            p.PostTypeId IN (1,2) AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, t.TagName
    ) tp ON tp.OwnerUserId = tu.UserId
    AND tp.TaggedPosts = (
        SELECT MAX(subtp.TaggedPosts)
        FROM (
            SELECT 
                COUNT(*) AS TaggedPosts
            FROM
                Posts p2
                CROSS JOIN LATERAL (
                    SELECT unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS TagName
                ) t2
            WHERE
                p2.OwnerUserId = tu.UserId
            GROUP BY t2.TagName
        ) subtp
    )
GROUP BY 
    tu.DisplayName, tu.AnswerCount, tu.QuestionCount, tu.TotalScore, tu.BadgeCount, ua.AcceptedAnswers, tp.TagName, tp.TaggedPosts, tp.AvgScore
ORDER BY
    tu.TotalScore DESC, ua.AcceptedAnswers DESC
LIMIT 25;