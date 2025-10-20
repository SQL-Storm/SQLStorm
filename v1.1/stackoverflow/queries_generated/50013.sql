-- {"query": "50013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1048} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score AS PostScore,
        p.CreationDate AS PostCreationDate,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.AcceptedAnswerId
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Reputation > 75000 AND p.CommunityOwnedDate IS NULL
),
UserStats AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(CASE WHEN PostTypeId = 2 THEN PostScore ELSE NULL END) AS AvgAnswerScore,
        SUM(ViewCount) AS TotalViewCount,
        SUM(FavoriteCount) AS TotalFavoriteCount,
        MAX(PostCreationDate) AS LastPostDate
    FROM
        UserActivity
    GROUP BY
        UserId, DisplayName, Reputation, UserCreationDate
    HAVING
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) > 10
        AND SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) > 50
),
UserBadges AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM
        Badges
    WHERE
        UserId IN (SELECT UserId FROM UserStats)
    GROUP BY
        UserId
),
QuestionResponseTimes AS (
    SELECT
        q.OwnerUserId AS UserId,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS AvgTimeToAcceptSeconds
    FROM
        Posts q
    JOIN
        Posts a ON q.AcceptedAnswerId = a.Id
    WHERE
        q.OwnerUserId IN (SELECT UserId FROM UserStats)
        AND q.PostTypeId = 1
    GROUP BY
        q.OwnerUserId
),
UserTagContributions AS (
    WITH TagRanking AS (
        SELECT
            UserId,
            Tag,
            COUNT(*) as TagCount,
            ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY COUNT(*) DESC, Tag ASC) as rn
        FROM (
            SELECT
                OwnerUserId AS UserId,
                unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS Tag
            FROM
                Posts
            WHERE
                OwnerUserId IN (SELECT UserId FROM UserStats)
                AND PostTypeId = 1
                AND Tags IS NOT NULL
        ) AS UserTags
        GROUP BY
            UserId, Tag
    )
    SELECT
        UserId,
        string_agg(Tag, ', ' ORDER BY rn) AS Top3Tags
    FROM
        TagRanking
    WHERE
        rn <= 3
    GROUP BY
        UserId
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalQuestions,
    us.TotalAnswers,
    CAST(us.AvgAnswerScore AS DECIMAL(10, 2)) AS AvgAnswerScore,
    us.TotalViewCount,
    ub.GoldBadges,
    ub.SilverBadges,
    utc.Top3Tags,
    qrt.AvgTimeToAcceptSeconds,
    (us.Reputation * 0.4 + us.TotalViewCount * 0.1 + ub.GoldBadges * 1000 + ub.SilverBadges * 100 - (qrt.AvgTimeToAcceptSeconds / 3600)) AS CompositeScore
FROM
    UserStats us
JOIN
    UserBadges ub ON us.UserId = ub.UserId
LEFT JOIN
    QuestionResponseTimes qrt ON us.UserId = qrt.UserId
LEFT JOIN
    UserTagContributions utc ON us.UserId = utc.UserId
WHERE
    ub.GoldBadges > 2
ORDER BY
    CompositeScore DESC,
    us.Reputation DESC
LIMIT 100;

