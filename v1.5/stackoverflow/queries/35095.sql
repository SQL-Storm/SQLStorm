-- {"query": "35095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 498} 
WITH TopAnswerers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AvgAnswerScore
    FROM
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 2 -- Answers
        AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(p.Id) > 50
),
UserComments AS (
    SELECT
        u.Id AS UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM
        Users u
        JOIN Comments c ON u.Id = c.UserId
    WHERE
        c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY
        u.Id
),
UserBadges AS (
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        b.Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY
        u.Id
)
SELECT
    ta.UserId,
    ta.DisplayName,
    ta.AnswerCount,
    ta.TotalAnswerScore,
    ROUND(ta.AvgAnswerScore,2) AS AvgAnswerScore,
    uc.CommentCount,
    ROUND(uc.AvgCommentScore,2) AS AvgCommentScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate
FROM
    TopAnswerers ta
    LEFT JOIN UserComments uc ON ta.UserId = uc.UserId
    LEFT JOIN UserBadges ub ON ta.UserId = ub.UserId
    JOIN Users u ON ta.UserId = u.Id
ORDER BY
    ta.TotalAnswerScore DESC,
    ta.AnswerCount DESC
LIMIT 50;