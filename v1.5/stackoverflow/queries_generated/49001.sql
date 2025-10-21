-- {"query": "49001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1799} 

WITH UserActivitySummary AS (
    -- Summarize user activity metrics over the last 5 years
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(u.LastAccessDate) AS LastAccessDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
    WHERE u.CreationDate <= (CURRENT_TIMESTAMP - INTERVAL '1 year') -- Only consider users active for at least 1 year
    GROUP BY u.Id, u.Reputation, u.LastAccessDate
),
UserBadgeMetrics AS (
    -- Count Gold, Silver, Bronze badges for users in the last 5 years
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    WHERE b.Date >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
    GROUP BY b.UserId
),
UserNegativeHistory AS (
    -- Identify users with deleted posts or offensive votes
    SELECT DISTINCT u.Id AS UserId
    FROM Users u
    WHERE EXISTS (
        SELECT 1
        FROM Posts p
        JOIN PostHistory ph ON p.Id = ph.PostId
        WHERE p.OwnerUserId = u.Id
          AND ph.PostHistoryTypeId = 12 -- Post Deleted
          AND ph.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
        LIMIT 1
    ) OR EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.UserId = u.Id
          AND v.VoteTypeId = 4 -- Offensive vote given by user
          AND v.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
        LIMIT 1
    ) OR EXISTS (
        SELECT 1
        FROM Posts p_voted
        JOIN Votes pv ON p_voted.Id = pv.PostId
        WHERE p_voted.OwnerUserId = u.Id
          AND pv.VoteTypeId = 4 -- Offensive vote received on user's post
          AND pv.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
        LIMIT 1
    )
),
UserHighQualityAnswerTags AS (
    -- Extract tags from parent questions for high-scoring answers in the last 5 years
    SELECT
        a.OwnerUserId AS UserId,
        LOWER(TRIM(unnest(string_to_array(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><')))) AS TagName,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate
    FROM Posts a -- Answers
    INNER JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1 -- Parent Questions
    WHERE
        a.PostTypeId = 2 -- Only answers
        AND a.Score >= 5 -- High-quality answers threshold
        AND a.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
        AND q.Tags IS NOT NULL
        AND LENGTH(q.Tags) > 2 -- Ensure tags exist and are not just '<>'
),
RankedUserTags AS (
    -- Rank tags by count of answers and total score per user
    SELECT
        uhat.UserId,
        uhat.TagName,
        COUNT(DISTINCT uhat.AnswerId) AS TaggedAnswersCount,
        SUM(uhat.AnswerScore) AS TotalTagScore,
        ROW_NUMBER() OVER (
            PARTITION BY uhat.UserId
            ORDER BY COUNT(DISTINCT uhat.AnswerId) DESC, SUM(uhat.AnswerScore) DESC
        ) AS TagRank
    FROM UserHighQualityAnswerTags uhat
    WHERE uhat.TagName != '' -- Exclude empty tags
    GROUP BY uhat.UserId, uhat.TagName
),
TopTagsPerUser AS (
    -- Select the top 3 most popular tags per user
    SELECT
        UserId,
        TagName,
        TaggedAnswersCount,
        TotalTagScore
    FROM RankedUserTags
    WHERE TagRank <= 3
)
SELECT
    uas.UserId,
    u.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalAnswerScore,
    uas.AvgAnswerScore,
    uas.TotalComments,
    COALESCE(ubm.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubm.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubm.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubm.TotalBadges, 0) AS TotalBadges,
    STRING_AGG(DISTINCT ttu.TagName || ' (' || ttu.TaggedAnswersCount || ' answers, score ' || ttu.TotalTagScore || ')', '; ') AS TopContributingTags,
    RANK() OVER (
        ORDER BY
            uas.Reputation DESC,
            uas.AvgAnswerScore DESC,
            COALESCE(ubm.GoldBadges, 0) DESC,
            COALESCE(ubm.SilverBadges, 0) DESC,
            uas.TotalAnswers DESC,
            uas.LastAccessDate DESC
    ) AS OverallInfluenceRank
FROM UserActivitySummary uas
INNER JOIN Users u ON uas.UserId = u.Id
LEFT JOIN UserBadgeMetrics ubm ON uas.UserId = ubm.UserId
LEFT JOIN UserNegativeHistory unh ON uas.UserId = unh.UserId
LEFT JOIN TopTagsPerUser ttu ON uas.UserId = ttu.UserId
WHERE
    uas.TotalAnswers >= 20 -- Minimum answers for consideration
    AND uas.AvgAnswerScore >= 15 -- Minimum average score for answers
    AND uas.Reputation >= 10000 -- Minimum reputation for "influential"
    AND unh.UserId IS NULL -- Exclude users with any negative history
    AND u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 50 -- Users with substantial 'About Me' section
    AND u.Views >= 500 -- Users with significant profile views
    AND uas.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '6 months') -- Recently active users
GROUP BY
    uas.UserId, u.DisplayName, uas.Reputation, uas.TotalPosts, uas.TotalQuestions,
    uas.TotalAnswers, uas.TotalAnswerScore, uas.AvgAnswerScore, uas.TotalComments,
    ubm.GoldBadges, ubm.SilverBadges, ubm.BronzeBadges, ubm.TotalBadges, uas.LastAccessDate
HAVING
    COUNT(ttu.TagName) >= 2 -- Ensure they contribute to at least two top tags
ORDER BY OverallInfluenceRank ASC
LIMIT 100;
