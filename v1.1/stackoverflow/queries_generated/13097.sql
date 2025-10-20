-- {"query": "13097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 771} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(NULLIF(p.Score, 0)) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    GROUP BY 
        u.Id, u.DisplayName
),
CommentMetrics AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(LENGTH(c.Text)) AS TotalCommentLength,
        AVG(NULLIF(c.Score, 0)) AS AvgCommentScore
    FROM
        Comments c
    WHERE
        c.CreationDate >= NOW() - INTERVAL '6 months'
    GROUP BY
        c.UserId
),
TopPerformers AS (
    SELECT
        u.UserId,
        u.DisplayName,
        u.TotalPosts,
        u.TotalQuestions,
        u.TotalAnswers,
        u.LastPostDate,
        u.AvgPostScore,
        c.TotalComments,
        c.TotalCommentLength,
        c.AvgCommentScore,
        DENSE_RANK() OVER (ORDER BY u.TotalPosts DESC, c.TotalComments DESC) AS PerformanceRank
    FROM
        UserActivity u
    LEFT JOIN
        CommentMetrics c ON u.UserId = c.UserId
    WHERE
        u.PostRank <= 100
),
RecentBadges AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM
        Badges b
    WHERE
        b.Date >= NOW() - INTERVAL '1 year'
    GROUP BY
        b.UserId
)
SELECT
    tp.UserId,
    tp.DisplayName,
    tp.TotalPosts,
    tp.TotalQuestions,
    tp.TotalAnswers,
    tp.LastPostDate,
    tp.AvgPostScore,
    COALESCE(tp.TotalComments, 0) AS TotalComments,
    COALESCE(tp.TotalCommentLength, 0) AS TotalCommentLength,
    COALESCE(tp.AvgCommentScore, 0) AS AvgCommentScore,
    tp.PerformanceRank,
    rb.BadgeCount,
    rb.BadgeNames
FROM
    TopPerformers tp
LEFT JOIN
    RecentBadges rb ON tp.UserId = rb.UserId
WHERE
    EXISTS (
        SELECT 1
        FROM Posts p
        WHERE
            p.OwnerUserId = tp.UserId
            AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.5
    )
ORDER BY
    tp.PerformanceRank, rb.BadgeCount DESC
LIMIT 50;
