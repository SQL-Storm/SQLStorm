-- {"query": "20099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1405} 
WITH PostDetails AS (
    -- Enrich post data with analytical info for experienced, high-reputation users
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.ParentId,
        -- Calculate time since the user's previous post of any type
        EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / 3600.0 AS HoursSinceLastPost,
        -- Rank posts by score within each post type for each user
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRankByScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId IN (SELECT Id FROM Users WHERE Reputation > 1000 AND CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years')
      AND p.CommunityOwnedDate IS NULL
),
UserPostSummary AS (
    -- Aggregate post statistics for each user
    SELECT
        pd.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN pd.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pd.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(pd.HoursSinceLastPost) AS AvgHoursBetweenPosts,
        SUM(pd.Score) AS TotalPostScore,
        MAX(pd.Score) AS MaxPostScore,
        SUM(CASE WHEN pd.PostRankByScore <= 10 THEN 1 ELSE 0 END) AS Top10ScorePosts,
        -- Calculate the user's answer acceptance rate by joining answers to their parent questions
        100.0 * COUNT(q.AcceptedAnswerId) / NULLIF(SUM(CASE WHEN pd.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AcceptanceRate
    FROM PostDetails pd
    LEFT JOIN Posts q ON pd.ParentId = q.Id AND q.AcceptedAnswerId = pd.PostId
    GROUP BY pd.OwnerUserId
    HAVING SUM(CASE WHEN pd.PostTypeId = 2 THEN 1 ELSE 0 END) > 20 -- Only users with a decent number of answers
),
UserBadgeSummary AS (
    -- Analyze user badges, including a correlated subquery for the first gold tag badge
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        (
            SELECT b_inner.Name
            FROM Badges b_inner
            WHERE b_inner.UserId = b.UserId
              AND b_inner.Class = 1
              AND b_inner.TagBased IS TRUE
            ORDER BY b_inner.Date
            LIMIT 1
        ) AS FirstGoldTagBadge
    FROM Badges b
    GROUP BY b.UserId
)
-- Final Select: Combine user, post, and badge data to create a comprehensive user profile score
SELECT
    u.DisplayName,
    u.Reputation,
    EXTRACT(YEAR FROM age(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate)) AS AccountAgeYears,
    ups.TotalPosts,
    ups.AnswerCount,
    ups.AcceptanceRate,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    ubs.FirstGoldTagBadge,
    -- Calculate a complex 'ContributionScore' to rank users
    (
        LOG(u.Reputation + 1) * 10
        + ups.TotalPostScore / 100.0
        + ups.AcceptanceRate * 5
        + COALESCE(ubs.GoldBadges, 0) * 20
    ) / (LOG(ups.AvgHoursBetweenPosts + 2)) AS ContributionScore,
    -- Categorize user based on their activity and badge profile
    CASE
        WHEN ubs.GoldBadges > 5 AND ups.AcceptanceRate > 50 THEN 'Community Pillar'
        WHEN ups.AnswerCount > ups.QuestionCount * 3 THEN 'Answer Specialist'
        WHEN ups.AvgHoursBetweenPosts < 24 THEN 'Frequent Contributor'
        ELSE 'Regular Member'
    END AS UserProfile,
    -- Use a subquery to find the number of "linked" posts from the user's posts
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 1 AND pl.PostId IN (SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = u.Id)
    ) AS OutboundLinkedPosts,
    -- Some string manipulation and NULL logic on user's profile
    UPPER(SUBSTRING(COALESCE(u.Location, 'Unknown') FROM 1 FOR 20)) AS SanitizedLocation
FROM Users u
JOIN UserPostSummary ups ON u.Id = ups.OwnerUserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
WHERE
    u.Reputation > 5000
    AND u.DownVotes < u.UpVotes / 10
    AND (ups.AcceptanceRate > 25 OR COALESCE(ubs.GoldBadges, 0) > 2)
    -- Filter out users who tend to make many short, low-score comments
    AND u.Id NOT IN (
        SELECT DISTINCT c.UserId
        FROM Comments c
        WHERE LENGTH(c.Text) < 15 AND c.Score < 0 AND c.UserId IS NOT NULL
        GROUP BY c.UserId
        HAVING COUNT(*) > 10
    )
ORDER BY
    ContributionScore DESC NULLS LAST,
    u.Reputation DESC
LIMIT 100;