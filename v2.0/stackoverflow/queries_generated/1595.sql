-- {"query": "1595.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3451} 
WITH UserPostStats AS (
    -- Aggregates various post-related statistics for each user.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN COALESCE(p.Score, 0) ELSE 0 END) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount, 0) ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN COALESCE(p.Score, 0) END) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        -- Count questions where this user accepted an answer
        COUNT(p.AcceptedAnswerId) FILTER (WHERE p.PostTypeId = 1) AS AcceptedAnswerCountForQuestions,
        -- Count answers provided by this user that were accepted on *any* question
        COUNT(p_ans.Id) FILTER (WHERE p_ans.AcceptedAnswerId IS NOT NULL AND p_ans.OwnerUserId = u.Id AND p_ans.PostTypeId = 2) AS AcceptedAnswersProvided
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts p_ans ON p.Id = p_ans.AcceptedAnswerId AND p_ans.OwnerUserId = u.Id -- For accepted answers *by* this user
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
UserEditActivity AS (
    -- Summarizes post editing activity for each user.
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS PostsEdited,
        COUNT(ph.Id) AS TotalEdits,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        -- Calculate average time difference between consecutive edits by the same user using LAG()
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate)))) FILTER (WHERE LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate) IS NOT NULL) AS AvgTimeBetweenEditsSeconds
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit Title, Edit Body, Edit Tags, Rollback Body
    GROUP BY ph.UserId
),
UserCommentEngagement AS (
    -- Aggregates comment statistics for each user.
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        AVG(COALESCE(c.Score, 0)) AS AvgCommentScore,
        COUNT(CASE WHEN c.Text ILIKE '%thanks%' THEN 1 END) AS ThanksComments,
        COUNT(CASE WHEN c.Text ILIKE '%duplicate%' THEN 1 END) AS DuplicateComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeSummary AS (
    -- Provides a summary of badge distribution for each user.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionTagUsage AS (
    -- Extracts tag information for questions, including first tag and tag count.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.Score,
        p.ViewCount,
        -- Extract the first tag from the tags string
        TRIM(BOTH '<>' FROM SPLIT_PART(p.Tags, '>', 1)) AS FirstTag,
        -- Count the number of tags using string_to_array
        ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) AS NumberOfTags
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserDuplicatePostCounts AS (
    -- Counts how many of a user's questions are linked as duplicates.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(pl.Id) AS DuplicatedQuestionsCount
    FROM Posts p
    JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.PostTypeId = 1 -- Only questions can be marked as duplicates
      AND pl.LinkTypeId = 3 -- LinkType 3 = Duplicate
    GROUP BY p.OwnerUserId
),
UserContributionMetrics AS (
    -- Combines all user-related statistics into a single, comprehensive view.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate AS UserCreationDate,
        u.AboutMe,
        u.WebsiteUrl,
        u.LastAccessDate,
        EXTRACT(DAY FROM (NOW() - u.CreationDate)) AS UserAgeInDays, -- Complicated calculation
        COALESCE(ups.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(ups.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(ups.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(ups.TotalQuestionViews, 0) AS TotalQuestionViews,
        COALESCE(ups.AvgPostScore, 0) AS AvgPostScore,
        COALESCE(uea.TotalEdits, 0) AS UserTotalEdits,
        COALESCE(uce.TotalComments, 0) AS UserTotalComments,
        COALESCE(ubs.GoldBadges, 0) AS UserGoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS UserSilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS UserBronzeBadges,
        COALESCE(uea.AvgTimeBetweenEditsSeconds, 0) AS AvgEditInterval,
        COALESCE(udpc.DuplicatedQuestionsCount, 0) AS DuplicatedQuestionsCount,
        -- Window functions
        RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(ups.TotalPostScore, 0) DESC) AS GlobalReputationRank,
        NTILE(10) OVER (ORDER BY COALESCE(ups.TotalQuestions, 0) DESC, COALESCE(ups.TotalAnswers, 0) DESC) AS TopActivityDecile,
        AVG(COALESCE(ups.AvgPostScore, 0)) OVER (PARTITION BY u.Location) AS AvgPostScoreInLocation,
        -- Correlated Subquery 1: Counts user's highly-viewed questions
        (
            SELECT COUNT(p_sub.Id)
            FROM Posts p_sub
            WHERE p_sub.OwnerUserId = u.Id
              AND p_sub.PostTypeId = 1
              AND p_sub.ViewCount > 10000
        ) AS HighViewQuestionCount,
        -- Correlated Subquery 2: Finds the most common tag associated with a user's questions
        (
            SELECT qtu_sub.FirstTag
            FROM QuestionTagUsage qtu_sub
            WHERE qtu_sub.OwnerUserId = u.Id
            GROUP BY qtu_sub.FirstTag
            ORDER BY COUNT(qtu_sub.FirstTag) DESC, MAX(qtu_sub.Score) DESC
            LIMIT 1
        ) AS MostCommonQuestionTag,
        -- Complex Calculation: User Engagement Score
        (
            (u.Reputation / 1000.0) * 0.4 +
            (COALESCE(uea.TotalEdits, 0) / 100.0) * 0.2 +
            (COALESCE(uce.TotalComments, 0) / 50.0) * 0.2 +
            (COALESCE(ubs.GoldBadges, 0) * 5 + COALESCE(ubs.SilverBadges, 0) * 2 + COALESCE(ubs.BronzeBadges, 0)) * 0.1 +
            (COALESCE(ups.TotalPostScore, 0) / 100.0) * 0.1
        ) AS UserEngagementScore,
        -- String Expression: Combines user display name and location
        COALESCE(u.DisplayName, 'Anonymous') || ' (' || COALESCE(u.Location, 'Unknown') || ')' AS UserLocationInfo,
        -- NULL Logic: Categorizes users based on their 'AboutMe' section
        CASE
            WHEN u.AboutMe IS NOT NULL AND CHAR_LENGTH(u.AboutMe) > 100 THEN 'Has Detailed AboutMe'
            WHEN u.AboutMe IS NOT NULL AND CHAR_LENGTH(u.AboutMe) <= 100 THEN 'Has Short AboutMe'
            ELSE 'No AboutMe'
        END AS AboutMeStatus,
        -- Categorizes users based on multiple criteria
        CASE
            WHEN u.Reputation >= 10000 AND COALESCE(ubs.GoldBadges, 0) >= 3 THEN 'Elite Contributor'
            WHEN COALESCE(ups.TotalQuestions, 0) >= 50 AND COALESCE(ups.AvgPostScore, 0) >= 10 THEN 'High Impact Questioner'
            WHEN COALESCE(uea.TotalEdits, 0) >= 100 THEN 'Proactive Editor'
            WHEN COALESCE(uce.TotalComments, 0) >= 200 AND COALESCE(uce.AvgCommentScore, 0) >= 5 THEN 'Engaged Commenter'
            ELSE 'General Participant'
        END AS UserCategory,
        AVG(qtu.NumberOfTags) AS AverageTagsPerQuestionOwned -- Aggregation on joined QuestionTagUsage
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
    LEFT JOIN UserEditActivity uea ON u.Id = uea.UserId
    LEFT JOIN UserCommentEngagement uce ON u.Id = uce.UserId
    LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
    LEFT JOIN UserDuplicatePostCounts udpc ON u.Id = udpc.UserId
    LEFT JOIN QuestionTagUsage qtu ON qtu.OwnerUserId = u.Id
    WHERE u.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Filter for relatively active users
      AND u.Reputation > 100 -- Filter out very low reputation users
    GROUP BY -- All non-aggregated columns in SELECT must be in GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate,
        u.AboutMe, u.WebsiteUrl, u.LastAccessDate,
        ups.TotalQuestions, ups.TotalAnswers, ups.TotalPostScore, ups.TotalQuestionViews, ups.AvgPostScore,
        uea.TotalEdits, uce.TotalComments, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
        uea.AvgTimeBetweenEditsSeconds, udpc.DuplicatedQuestionsCount
)
-- Set Operator: UNION ALL to combine two distinct segments of active users
-- Segment 1: High-tier contributors (reputation, gold badges, high engagement score)
SELECT
    ucm.UserId,
    ucm.DisplayName,
    ucm.Reputation,
    ucm.UserCategory,
    ucm.UserEngagementScore,
    ucm.GlobalReputationRank,
    ucm.MostCommonQuestionTag,
    ucm.UserLocationInfo,
    ucm.AboutMeStatus,
    'High-Tier Contributor' AS SegmentType,
    ucm.TotalQuestions,
    ucm.TotalAnswers,
    ucm.UserTotalEdits,
    ucm.UserTotalComments
FROM UserContributionMetrics ucm
WHERE ucm.UserEngagementScore > 100 -- Threshold for high engagement
  AND ucm.GlobalReputationRank <= 5000 -- Top percentile by reputation
  AND ucm.UserGoldBadges >= 1
  AND (LOWER(ucm.Location) LIKE '%london%' OR LOWER(ucm.Location) LIKE '%paris%' OR ucm.Location IS NULL) -- Complex predicate with string expression and NULL logic
  AND ucm.HighViewQuestionCount >= 5 -- Users with multiple highly-viewed questions
ORDER BY ucm.UserEngagementScore DESC, ucm.GlobalReputationRank ASC
LIMIT 200

UNION ALL

-- Segment 2: Active community members (editing, commenting, but not necessarily top reputation)
SELECT
    ucm.UserId,
    ucm.DisplayName,
    ucm.Reputation,
    ucm.UserCategory,
    ucm.UserEngagementScore,
    ucm.GlobalReputationRank,
    ucm.MostCommonQuestionTag,
    ucm.UserLocationInfo,
    ucm.AboutMeStatus,
    'Active Community Member' AS SegmentType,
    ucm.TotalQuestions,
    ucm.TotalAnswers,
    ucm.UserTotalEdits,
    ucm.UserTotalComments
FROM UserContributionMetrics ucm
WHERE ucm.UserTotalEdits >= 50 -- Significant editing activity
  AND ucm.UserTotalComments >= 100 -- Significant commenting activity
  AND ucm.AvgEditInterval < 86400 * 7 -- Average edit interval less than 7 days (in seconds)
  AND ucm.Reputation BETWEEN 500 AND 9999 -- Decent but not elite reputation
  AND ucm.TotalQuestions + ucm.TotalAnswers >= 20 -- Minimum post contribution
  AND (ucm.WebsiteUrl IS NOT NULL OR ucm.AboutMe IS NOT NULL) -- Has some profile information (NULL logic)
ORDER BY ucm.UserEngagementScore DESC, ucm.UserTotalEdits DESC
LIMIT 200;