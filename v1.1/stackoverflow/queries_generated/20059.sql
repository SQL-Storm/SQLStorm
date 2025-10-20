-- {"query": "20059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1711} 

WITH UserContributionDetails AS (
    -- Step 1: Aggregate user post and comment statistics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.AboutMe,
        COUNT(DISTINCT q.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COALESCE(SUM(DISTINCT q.ViewCount), 0) AS TotalQuestionViews,
        COALESCE(SUM(DISTINCT a.Score), 0) AS TotalAnswerScore,
        COALESCE(AVG(a.Score), 0) AS AverageAnswerScore,
        SUM(CASE WHEN a.Id = q_parent.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers,
        MIN(a.CreationDate) AS FirstAnswerDate,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM
        Users u
    LEFT JOIN
        Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1 -- Questions
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers
    LEFT JOIN
        Posts q_parent ON a.ParentId = q_parent.Id -- Parent question for an answer
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    WHERE
        u.Reputation > 1500 AND u.CreationDate < (CURRENT_DATE - INTERVAL '2 year')
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.AboutMe
),
UserBadgeRanks AS (
    -- Step 2: Calculate badge counts and rank users within badge classes
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (SELECT ph.CreationDate
         FROM PostHistory ph
         WHERE ph.UserId = b.UserId AND ph.PostHistoryTypeId = 24 -- Suggested Edit Applied
         ORDER BY ph.CreationDate ASC
         LIMIT 1
        ) AS FirstApprovedEditDate,
        RANK() OVER (PARTITION BY Class ORDER BY COUNT(*) DESC) AS RankInClass
    FROM
        Badges b
    WHERE
        b.UserId IN (SELECT UserId FROM UserContributionDetails)
    GROUP BY
        b.UserId, b.Class
),
UserPrimaryTag AS (
    -- Step 3: Determine user's primary tag based on cumulative answer score using window functions
    SELECT
        OwnerUserId,
        Tag,
        TotalTagScore
    FROM (
        SELECT
            p.OwnerUserId,
            t.tag,
            SUM(p.Score) AS TotalTagScore,
            ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC, COUNT(t.tag) DESC) as rn
        FROM
            Posts p
        CROSS JOIN LATERAL
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
        WHERE
            p.PostTypeId = 1 -- Questions
            AND p.OwnerUserId IS NOT NULL
            AND p.Tags IS NOT NULL
        GROUP BY
            p.OwnerUserId, t.tag
    ) AS TagScores
    WHERE rn = 1
)
-- Final Select: Combine all CTEs to create a comprehensive user profile and a composite score
SELECT
    ucd.DisplayName,
    ucd.Reputation,
    ucd.QuestionCount,
    ucd.AnswerCount,
    ucd.TotalQuestionViews,
    ucd.TotalAnswerScore,
    CAST(ucd.AverageAnswerScore AS DECIMAL(10, 2)) AS AverageAnswerScore,
    CASE
        WHEN ucd.AnswerCount > 0 THEN CAST(ucd.AcceptedAnswers AS DECIMAL) / ucd.AnswerCount
        ELSE 0
    END AS AcceptedAnswerRate,
    COALESCE(ubr_gold.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubr_silver.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubr_bronze.BronzeBadges, 0) AS BronzeBadges,
    upt.Tag AS PrimaryTag,
    upt.TotalTagScore AS PrimaryTagScore,
    -- Complicated calculation for a 'ContributionScore'
    (
        (ucd.TotalAnswerScore * 0.4) +
        (ucd.TotalQuestionViews / 1000.0 * 0.1) +
        (ucd.AcceptedAnswers * 15 * 0.2) +
        (COALESCE(ubr_gold.GoldBadges, 0) * 100 * 0.15) +
        (COALESCE(ubr_silver.SilverBadges, 0) * 20 * 0.1) +
        (ucd.CommentCount * 0.05) -
        (EXTRACT(YEAR FROM AGE(CURRENT_DATE, ucd.CreationDate)) * 10)
    ) AS ContributionScore,
    -- Correlated subquery to find the title of the user's most recent controversial post (high score, many comments)
    (SELECT p.Title
     FROM Posts p
     WHERE p.OwnerUserId = ucd.UserId
       AND p.CommentCount > 20
       AND p.Score < 0
     ORDER BY p.LastActivityDate DESC
     LIMIT 1) AS LastControversialPost,
    -- String manipulation and NULL logic
    UPPER(SUBSTRING(COALESCE(ucd.Location, 'LOCATION_UNKNOWN'), 1, 15)) || '...' AS FormattedLocation,
    -- Set operator used inside a subquery for existence check
    EXISTS (
        SELECT 1 FROM Votes v WHERE v.UserId = ucd.UserId AND v.VoteTypeId = 8 -- BountyStart
        UNION ALL
        SELECT 1 FROM Votes v WHERE v.UserId = ucd.UserId AND v.VoteTypeId = 5 -- Favorite
    ) AS HasPlacedBountyOrFavorite
FROM
    UserContributionDetails ucd
LEFT JOIN
    UserBadgeRanks ubr_gold ON ucd.UserId = ubr_gold.UserId AND ubr_gold.RankInClass = 1
LEFT JOIN
    UserBadgeRanks ubr_silver ON ucd.UserId = ubr_silver.UserId AND ubr_silver.RankInClass = 2
LEFT JOIN
    UserBadgeRanks ubr_bronze ON ucd.UserId = ubr_bronze.UserId AND ubr_bronze.RankInClass = 3
LEFT JOIN
    UserPrimaryTag upt ON ucd.UserId = upt.OwnerUserId
WHERE
    ucd.AnswerCount > ucd.QuestionCount -- More answers than questions
    AND (ucd.LastAnswerDate > ucd.FirstAnswerDate + INTERVAL '1 year') -- Active for more than a year
    AND LENGTH(ucd.AboutMe) > 100 -- Has a detailed AboutMe section
ORDER BY
    ContributionScore DESC,
    ucd.Reputation DESC
LIMIT 250;
