-- {"query": "20043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1616} 

WITH UserMetrics AS (
    -- Step 1: Identify a base set of active, high-reputation users and gather their badge counts and basic info.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 86400.0) AS AccountAgeDays,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        u.WebsiteUrl,
        u.Location
    FROM
        Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE
        u.Reputation > 50000
        AND u.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
        AND u.Id > 0
),
PostAndAnswerStats AS (
    -- Step 2: For the selected users, calculate detailed statistics about their questions and answers.
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AverageScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavorites,
        MAX(p.CreationDate) as LastPostDate,
        -- Use a window function to find the time difference between a user's consecutive posts
        AVG(EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / 3600.0) AS AvgHoursBetweenPosts
    FROM
        Posts p
    WHERE
        p.OwnerUserId IN (SELECT UserId FROM UserMetrics) AND p.CommunityOwnedDate IS NULL
    GROUP BY
        p.OwnerUserId
),
UserCurationActivity AS (
    -- Step 3: Analyze curation activities like editing and participating in close/reopen votes.
    SELECT
        ph.UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId END) AS EditedPostsCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenVotes
    FROM
        PostHistory ph
    WHERE
        ph.UserId IN (SELECT UserId FROM UserMetrics)
    GROUP BY
        ph.UserId
)
-- Step 4: Final aggregation and calculation of a composite "Power User Score".
SELECT
    um.DisplayName,
    um.Reputation,
    um.AccountAgeDays,
    pas.QuestionCount,
    pas.AnswerCount,
    -- Define a user "type" based on their primary contribution
    CASE
        WHEN pas.QuestionCount > pas.AnswerCount * 1.5 THEN 'Inquisitor'
        WHEN pas.AnswerCount > pas.QuestionCount * 1.5 THEN 'Mentor'
        WHEN uca.EditedPostsCount > (pas.QuestionCount + pas.AnswerCount) THEN 'Curator'
        ELSE 'Contributor'
    END AS UserType,
    -- Correlated subquery to find the title of the user's highest-scoring question
    (SELECT Title FROM Posts p_inner WHERE p_inner.OwnerUserId = um.UserId AND p_inner.PostTypeId = 1 ORDER BY Score DESC, ViewCount DESC NULLS LAST LIMIT 1) AS TopQuestionTitle,
    -- Calculate a complex, weighted "Power Score"
    (
        (LN(um.Reputation + 1) * 10) +
        (pas.AverageScore * 2) +
        (pas.AnswerCount * 1.5) -
        (pas.QuestionCount * 0.5) +
        (uca.EditedPostsCount * 1.2) +
        (um.GoldBadges * 50) +
        (um.SilverBadges * 20) +
        (LN(pas.TotalViews + 1) * 5)
    ) / LN(um.AccountAgeDays + 10) AS PowerScore,
    -- Rank users within each calculated "UserType" based on their score
    DENSE_RANK() OVER (PARTITION BY
        CASE
            WHEN pas.QuestionCount > pas.AnswerCount * 1.5 THEN 'Inquisitor'
            WHEN pas.AnswerCount > pas.QuestionCount * 1.5 THEN 'Mentor'
            WHEN uca.EditedPostsCount > (pas.QuestionCount + pas.AnswerCount) THEN 'Curator'
            ELSE 'Contributor'
        END
        ORDER BY
        (
            (LN(um.Reputation + 1) * 10) +
            (pas.AverageScore * 2) +
            (pas.AnswerCount * 1.5) -
            (pas.QuestionCount * 0.5) +
            (uca.EditedPostsCount * 1.2) +
            (um.GoldBadges * 50) +
            (um.SilverBadges * 20) +
            (LN(pas.TotalViews + 1) * 5)
        ) / LN(um.AccountAgeDays + 10) DESC
    ) AS RankInType,
    pas.AvgHoursBetweenPosts,
    -- Use string functions and NULL logic on user location
    CONCAT(
        'Location: ',
        COALESCE(NULLIF(TRIM(UPPER(SUBSTRING(um.Location, 1, 20))), ''), 'UNKNOWN')
    ) AS FormattedLocation
FROM
    UserMetrics um
JOIN PostAndAnswerStats pas ON um.UserId = pas.OwnerUserId
LEFT JOIN UserCurationActivity uca ON um.UserId = uca.UserId
WHERE
    pas.AnswerCount > 10
    AND pas.AverageScore > 5
    AND um.GoldBadges > 0
    AND um.Reputation > (SELECT AVG(Reputation) FROM Users) -- Filter against a global aggregate
ORDER BY
    PowerScore DESC
LIMIT 200;
