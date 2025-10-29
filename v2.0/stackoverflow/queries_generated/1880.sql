-- {"query": "1880.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3978} 

WITH UserPostAggregates AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        u.Views,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScoreSum,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(p.CreationDate) AS LatestPostDate,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoriteCounts,
        -- Correlated subquery 1: Count of questions with accepted answers
        (
            SELECT COUNT(DISTINCT p_q.Id)
            FROM Posts p_q
            WHERE p_q.OwnerUserId = u.Id
              AND p_q.PostTypeId = 1
              AND p_q.AcceptedAnswerId IS NOT NULL
              AND p_q.CreationDate >= u.CreationDate
        ) AS QuestionsWithAcceptedAnswer,
        -- Correlated subquery 2: Count of user's answers that were accepted by others
        (
            SELECT COUNT(DISTINCT p_a.Id)
            FROM Posts p_a
            WHERE p_a.OwnerUserId = u.Id
              AND p_a.PostTypeId = 2
              AND EXISTS (SELECT 1 FROM Posts p_q_acc WHERE p_q_acc.AcceptedAnswerId = p_a.Id AND p_q_acc.CreationDate >= u.CreationDate)
        ) AS AcceptedAnswersGiven
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location,
        u.AboutMe, u.Views, u.UpVotes, u.DownVotes
    HAVING COUNT(p.Id) > 0 -- Only consider users who have made at least one post
),
UserVoteAndBadgeStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived, -- UpMod
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived, -- DownMod
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived -- Favorite (bookmarks)
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 5) -- Only considering certain vote types for aggregation
    GROUP BY u.Id
),
TagPerformance AS (
    SELECT
        UNNEST(string_to_array(TRIM(REPLACE(REPLACE(p.Tags, '><', '|'), '<', ''), '>'), '|')) AS TagName,
        COUNT(DISTINCT p.Id) AS TagPostCount,
        SUM(p.Score) AS TagTotalScore,
        AVG(p.Score) AS TagAvgScore,
        AVG(p.ViewCount) AS TagAvgViewCount,
        MAX(p.CreationDate) AS LastTagActivity
    FROM Posts p
    WHERE p.Tags IS NOT NULL
      AND p.Tags != ''
      AND p.PostTypeId = 1 -- Tags are primarily associated with questions
      AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years' -- Focus on recent tag activity
    GROUP BY UNNEST(string_to_array(TRIM(REPLACE(REPLACE(p.Tags, '><', '|'), '<', ''), '>'), '|'))
    HAVING COUNT(DISTINCT p.Id) > 50 -- Filter for significant tags
       AND AVG(p.Score) > 3 -- Tags with generally positive sentiment
),
RankedTags AS (
    SELECT
        TagName,
        TagTotalScore,
        TagAvgScore,
        TagPostCount,
        TagAvgViewCount,
        ROW_NUMBER() OVER (ORDER BY TagTotalScore DESC, TagAvgViewCount DESC) AS TagScoreRank
    FROM TagPerformance
    WHERE TagName IS NOT NULL
),
UserDetailedMetrics AS (
    SELECT
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.UserCreationDate,
        upa.LastAccessDate,
        upa.Location,
        upa.AboutMe,
        upa.Views,
        upa.UserUpVotes,
        upa.UserDownVotes,
        upa.TotalPosts,
        upa.TotalQuestions,
        upa.TotalAnswers,
        upa.QuestionScoreSum,
        upa.AnswerScoreSum,
        upa.AvgQuestionViewCount,
        upa.LatestPostDate,
        upa.TotalFavoriteCounts,
        upa.QuestionsWithAcceptedAnswer,
        upa.AcceptedAnswersGiven,
        uvbs.TotalBadges,
        uvbs.GoldBadges,
        uvbs.SilverBadges,
        uvbs.BronzeBadges,
        uvbs.UpVotesReceived,
        uvbs.DownVotesReceived,
        uvbs.FavoritesReceived,
        -- Calculate some derived metrics with NULL logic
        (upa.Reputation * 1.0 / NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - upa.UserCreationDate)) / 86400, 0)) AS RepPerDayLifetime, -- Reputation per day active
        COALESCE(upa.QuestionScoreSum, 0) + COALESCE(upa.AnswerScoreSum, 0) AS OverallPostScore,
        NULLIF(upa.AcceptedAnswersGiven, 0) * 1.0 / NULLIF(upa.TotalAnswers, 0) AS AnswerAcceptanceRate,
        NULLIF(upa.QuestionsWithAcceptedAnswer, 0) * 1.0 / NULLIF(upa.TotalQuestions, 0) AS QuestionAcceptanceRate,
        COALESCE(upa.TotalQuestions, 0) * 1.0 / NULLIF(COALESCE(upa.TotalQuestions, 0) + COALESCE(upa.TotalAnswers, 0), 0) AS QuestionRatio,
        COALESCE(LENGTH(upa.AboutMe), 0) AS AboutMeCharCount,
        AGE(CURRENT_TIMESTAMP, upa.LastAccessDate) AS LastAccessTimeDelta
    FROM UserPostAggregates upa
    LEFT JOIN UserVoteAndBadgeStats uvbs ON upa.UserId = uvbs.UserId
    WHERE upa.Reputation > 500 -- Filter out very low rep users
      AND upa.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' -- Active in last year
      AND upa.DisplayName IS NOT NULL
      AND upa.AboutMe IS NOT NULL -- Ensure 'AboutMe' exists for string operations
),
UserInfluenceScores AS (
    SELECT
        udm.UserId,
        udm.DisplayName,
        udm.Reputation,
        udm.UserCreationDate,
        udm.LastAccessDate,
        udm.Location,
        udm.AboutMe,
        udm.Views,
        udm.TotalPosts,
        udm.TotalQuestions,
        udm.TotalAnswers,
        udm.GoldBadges,
        udm.SilverBadges,
        udm.BronzeBadges,
        udm.OverallPostScore,
        udm.AnswerAcceptanceRate,
        udm.QuestionAcceptanceRate,
        udm.AboutMeCharCount,
        -- Calculate a preliminary influence score
        (
            udm.Reputation * 0.05
            + COALESCE(udm.GoldBadges, 0) * 100
            + COALESCE(udm.SilverBadges, 0) * 50
            + COALESCE(udm.BronzeBadges, 0) * 10
            + COALESCE(udm.OverallPostScore, 0) * 0.2
            + COALESCE(udm.Views, 0) * 0.005
            + COALESCE(udm.TotalFavoriteCounts, 0) * 1.5
            + COALESCE(udm.AnswerAcceptanceRate, 0) * 30 -- Answers being accepted is highly valuable
            + COALESCE(udm.QuestionAcceptanceRate, 0) * 15 -- Questions having accepted answers
            + (CASE WHEN udm.LastAccessTimeDelta < INTERVAL '3 months' THEN 25 ELSE 0 END) -- Bonus for very recent activity
        ) AS BaseInfluenceScore,
        -- Aggregate highly ranked tag interests for each user
        ARRAY_AGG(DISTINCT rt.TagName) FILTER (WHERE rt.TagScoreRank <= 25) AS Top25TagInterests,
        COUNT(DISTINCT rt.TagName) FILTER (WHERE rt.TagScoreRank <= 25) AS CountTop25TagInterests
    FROM UserDetailedMetrics udm
    -- LEFT JOIN to link users to the tags they post in, using LATERAL UNNEST for tag explosion
    LEFT JOIN Posts p ON udm.UserId = p.OwnerUserId AND p.Tags IS NOT NULL AND p.Tags != '' AND p.PostTypeId = 1
    LEFT JOIN LATERAL UNNEST(string_to_array(TRIM(REPLACE(REPLACE(p.Tags, '><', '|'), '<', ''), '>'), '|')) AS post_tag(TagName) ON TRUE
    LEFT JOIN RankedTags rt ON post_tag.TagName = rt.TagName
    GROUP BY
        udm.UserId, udm.DisplayName, udm.Reputation, udm.UserCreationDate, udm.LastAccessDate,
        udm.Location, udm.AboutMe, udm.Views, udm.TotalPosts, udm.TotalQuestions,
        udm.TotalAnswers, udm.GoldBadges, udm.SilverBadges, udm.BronzeBadges,
        udm.OverallPostScore, udm.AnswerAcceptanceRate, udm.QuestionAcceptanceRate,
        udm.AboutMeCharCount, udm.LastAccessTimeDelta
    HAVING COALESCE(udm.OverallPostScore, 0) > 20 -- Ensure they have a sufficiently positive score
       AND udm.TotalPosts > 5 -- Users with minimal activity are filtered
),
FinalUserRanking AS (
    SELECT
        uis.UserId,
        uis.DisplayName,
        uis.Reputation,
        uis.TotalPosts,
        uis.TotalQuestions,
        uis.TotalAnswers,
        uis.GoldBadges,
        uis.SilverBadges,
        uis.BronzeBadges,
        uis.BaseInfluenceScore,
        uis.Top25TagInterests,
        uis.CountTop25TagInterests,
        -- Final combined influence score, with bonuses for specific criteria
        (
            uis.BaseInfluenceScore
            + (CASE WHEN uis.CountTop25TagInterests > 0 THEN uis.CountTop25TagInterests * 15 ELSE 0 END) -- Bonus for engaging in hot tags
            + (CASE WHEN uis.Location ILIKE '%California%' OR uis.Location ILIKE '%New York%' THEN 10 ELSE 0 END) -- Location-based bonus (arbitrary)
            + (CASE WHEN uis.AboutMeCharCount > 800 AND uis.AboutMe ILIKE '%developer%' THEN 20 ELSE 0 END) -- Bonus for detailed tech-oriented AboutMe
        ) AS FinalInfluenceScore,
        -- Window function: Rank users by their FinalInfluenceScore
        RANK() OVER (ORDER BY uis.FinalInfluenceScore DESC, uis.Reputation DESC, uis.LastAccessDate DESC) AS OverallInfluenceRank,
        -- NTILE for assigning users to influence tiers
        NTILE(10) OVER (ORDER BY uis.FinalInfluenceScore DESC) AS InfluenceTier,
        -- String expression and NULL handling in SELECT for a summary
        CONCAT(
            'User ID: ', uis.UserId,
            ' (Display Name: ', COALESCE(uis.DisplayName, 'N/A'), ')',
            CASE
                WHEN uis.TotalQuestions > uis.TotalAnswers * 1.5 THEN ' | Question Lead'
                WHEN uis.TotalAnswers > uis.TotalQuestions * 1.5 THEN ' | Answer Lead'
                ELSE ' | Balanced Contributor'
            END,
            ' | Last Active: ', TO_CHAR(uis.LastAccessDate, 'YYYY-MM-DD HH24:MI'),
            ' | Location: ', COALESCE(UPPER(SUBSTRING(uis.Location, 1, 1)) || LOWER(SUBSTRING(uis.Location, 2)), 'Undisclosed')
        ) AS UserSummaryText,
        -- More complex CASE WHEN logic for user contribution category
        CASE
            WHEN uis.Reputation >= 200000 AND uis.GoldBadges >= 10 THEN 'Elite StackMaster'
            WHEN uis.Reputation >= 100000 AND uis.GoldBadges >= 3 THEN 'Distinguished Architect'
            WHEN uis.Reputation >= 50000 AND uis.SilverBadges >= 5 THEN 'Principal Engineer'
            WHEN uis.TotalPosts >= 200 AND uis.OverallPostScore >= 1000 THEN 'Proactive Contributor'
            WHEN uis.Reputation >= 10000 THEN 'Established Member'
            ELSE 'Engaged Participant'
        END AS UserCategory
    FROM UserInfluenceScores uis
    WHERE uis.FinalInfluenceScore IS NOT NULL AND uis.FinalInfluenceScore > 0
),
TopQuestionContributors AS (
    SELECT
        FUR.UserId,
        FUR.DisplayName,
        FUR.Reputation,
        'Question-Focused Leader' AS ContributionType,
        (FUR.FinalInfluenceScore * (1.0 + COALESCE(FUR.TotalQuestions, 0.0) / NULLIF(FUR.TotalPosts, 0.0) * 0.75)) AS WeightedInfluenceScore,
        FUR.UserSummaryText AS Details
    FROM FinalUserRanking FUR
    WHERE FUR.TotalQuestions > FUR.TotalAnswers
      AND FUR.Reputation >= 10000
      AND FUR.InfluenceTier <= 5
      AND FUR.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '6 months'
),
TopAnswerContributors AS (
    SELECT
        FUR.UserId,
        FUR.DisplayName,
        FUR.Reputation,
        'Answer-Focused Expert' AS ContributionType,
        (FUR.FinalInfluenceScore * (1.0 + COALESCE(FUR.TotalAnswers, 0.0) / NULLIF(FUR.TotalPosts, 0.0) * 0.75)) AS WeightedInfluenceScore,
        FUR.UserSummaryText AS Details
    FROM FinalUserRanking FUR
    WHERE FUR.TotalAnswers > FUR.TotalQuestions
      AND FUR.Reputation >= 10000
      AND FUR.InfluenceTier <= 5
      AND FUR.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '6 months'
)
-- Set operator: UNION ALL to combine the top question-focused and answer-focused users.
-- Further filtering to select the truly elite from each category.
SELECT
    tqc.UserId,
    tqc.DisplayName,
    tqc.Reputation,
    tqc.ContributionType,
    tqc.WeightedInfluenceScore,
    tqc.Details,
    'Top 1% Segment' AS UserSegment
FROM TopQuestionContributors tqc
WHERE tqc.WeightedInfluenceScore > (SELECT AVG(WeightedInfluenceScore) * 2 FROM TopQuestionContributors) -- Correlated subquery in WHERE clause for elite status
ORDER BY tqc.WeightedInfluenceScore DESC, tqc.Reputation DESC
LIMIT 25

UNION ALL

SELECT
    tac.UserId,
    tac.DisplayName,
    tac.Reputation,
    tac.ContributionType,
    tac.WeightedInfluenceScore,
    tac.Details,
    'Top 1% Segment' AS UserSegment
FROM TopAnswerContributors tac
WHERE tac.WeightedInfluenceScore > (SELECT AVG(WeightedInfluenceScore) * 2 FROM TopAnswerContributors) -- Correlated subquery in WHERE clause for elite status
ORDER BY tac.WeightedInfluenceScore DESC, tac.Reputation DESC
LIMIT 25;
