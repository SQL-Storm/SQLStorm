-- {"query": "35093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 627} 
WITH TopActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.Score) AS TotalScore
    FROM
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.CreationDate > NOW() - INTERVAL '180 days'
        AND p.PostTypeId IN (1,2)
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(DISTINCT p.Id) > 20
        AND SUM(p.Score) > 50
),
UserAnswerMetrics AS (
    SELECT
        u.UserId,
        COUNT(DISTINCT a.Id) AS AnswersCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.Score > 10 THEN 1 ELSE 0 END) AS HighScoringAnswers
    FROM
        TopActiveUsers u
        JOIN Posts a ON a.OwnerUserId = u.UserId AND a.PostTypeId = 2
    GROUP BY
        u.UserId
),
UserCommentMetrics AS (
    SELECT
        u.UserId,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        AVG(c.Score) AS AvgCommentScore
    FROM
        TopActiveUsers u
        JOIN Comments c ON c.UserId = u.UserId
    WHERE
        c.CreationDate > NOW() - INTERVAL '180 days'
    GROUP BY
        u.UserId
),
UserRecentBadges AS (
    SELECT
        u.UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM
        TopActiveUsers u
        JOIN Badges b ON b.UserId = u.UserId
    WHERE
        b.Date > NOW() - INTERVAL '180 days'
    GROUP BY
        u.UserId
)
SELECT
    u.UserId,
    u.DisplayName,
    u.PostsCount,
    u.TotalViews,
    u.TotalScore,
    am.AnswersCount,
    COALESCE(am.AvgAnswerScore,0) AS AvgAnswerScore,
    am.HighScoringAnswers,
    cm.CommentsCount,
    COALESCE(cm.AvgCommentScore,0) AS AvgCommentScore,
    rb.GoldBadges,
    rb.SilverBadges,
    rb.BronzeBadges
FROM
    TopActiveUsers u
    LEFT JOIN UserAnswerMetrics am ON u.UserId = am.UserId
    LEFT JOIN UserCommentMetrics cm ON u.UserId = cm.UserId
    LEFT JOIN UserRecentBadges rb ON u.UserId = rb.UserId
ORDER BY
    u.TotalScore DESC,
    u.TotalViews DESC
LIMIT 50;