-- {"query": "1910.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3502} 
WITH UserBaseActivity AS (
    -- Summarize core activity for each user
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(GREATEST(p.LastActivityDate, c.CreationDate, u.LastAccessDate)) AS LatestActivityGlobally
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostDetailedMetrics AS (
    -- Calculate detailed metrics for each question and answer post, including ranking and comparison
    SELECT
        p.Id AS Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.Title,
        p.Tags,
        COALESCE(p.LastEditorDisplayName, u_editor.DisplayName, 'Community') AS LastEditorInfo,
        p.LastEditDate,
        p.LastActivityDate,
        -- Calculate Score-to-View ratio, handling potential division by zero and NULLs
        COALESCE(CAST(p.Score AS NUMERIC(10,2)) / NULLIF(p.ViewCount, 0), 0.0) AS ScoreViewRatio,
        -- Correlated subquery: Determines if the post owner accepted their own answer for this question
        (CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
              THEN (SELECT COUNT(1) FROM Posts pa WHERE pa.Id = p.AcceptedAnswerId AND pa.OwnerUserId = p.OwnerUserId)
              ELSE 0 END) AS SelfAcceptedAnswerForQuestion,
        -- Window function: Rank posts by score within each PostType
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByPostTypeScore,
        -- Window function: Average score for posts of the same type within the same calendar month
        AVG(p.Score) OVER(PARTITION BY p.PostTypeId, DATE_TRUNC('month', p.CreationDate)) AS AvgMonthlyPostTypeScore
    FROM Posts p
    LEFT JOIN Users u_editor ON p.LastEditorUserId = u_editor.Id
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL -- Only questions and answers with an owner
),
UserPostAggregates AS (
    -- Aggregate post-specific metrics per user for their top posts
    SELECT
        pdm.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN pdm.PostTypeId = 1 AND pdm.RankByPostTypeScore <= 5 THEN pdm.Id END) AS Top5QuestionsCount,
        COUNT(DISTINCT CASE WHEN pdm.PostTypeId = 2 AND pdm.RankByPostTypeScore <= 5 THEN pdm.Id END) AS Top5AnswersCount,
        SUM(pdm.SelfAcceptedAnswerForQuestion) AS TotalSelfAcceptedAnswers,
        MAX(CASE WHEN pdm.PostTypeId = 1 AND pdm.RankByPostTypeScore = 1 THEN pdm.Id END) AS BestQuestionId,
        MAX(CASE WHEN pdm.PostTypeId = 1 AND pdm.RankByPostTypeScore = 1 THEN pdm.Title END) AS BestQuestionTitle,
        MAX(CASE WHEN pdm.PostTypeId = 1 AND pdm.RankByPostTypeScore = 1 THEN pdm.PostScore END) AS BestQuestionScore,
        MAX(CASE WHEN pdm.PostTypeId = 2 AND pdm.RankByPostTypeScore = 1 THEN pdm.Id END) AS BestAnswerId,
        MAX(CASE WHEN pdm.PostTypeId = 2 AND pdm.RankByPostTypeScore = 1 THEN pdm.Title END) AS BestAnswerTitle,
        MAX(CASE WHEN pdm.PostTypeId = 2 AND pdm.RankByPostTypeScore = 1 THEN pdm.PostScore END) AS BestAnswerScore
    FROM PostDetailedMetrics pdm
    GROUP BY pdm.OwnerUserId
),
UserTopTagContributions AS (
    -- Identify and rank a user's top contributed tags based on post score
    SELECT
        utc.OwnerUserId,
        utc.TagNameCleaned,
        utc.TagContributionScore,
        ROW_NUMBER() OVER(PARTITION BY utc.OwnerUserId ORDER BY utc.TagContributionScore DESC, utc.TagNameCleaned ASC) AS rn_tag_per_user
    FROM (
        SELECT
            pdm.OwnerUserId,
            REPLACE(REPLACE(TRIM(SUBSTRING(unnest(string_to_array(SUBSTRING(pdm.Tags, 2, LENGTH(pdm.Tags) - 2), '><')), 1, 50)), ' ', ''), '-', '') AS TagNameCleaned,
            SUM(pdm.PostScore) AS TagContributionScore
        FROM PostDetailedMetrics pdm
        WHERE pdm.PostTypeId = 1 AND pdm.Tags IS NOT NULL AND LENGTH(pdm.Tags) > 2
        GROUP BY pdm.OwnerUserId, TagNameCleaned
        HAVING SUM(pdm.PostScore) > 0
    ) AS utc
),
TopUserTagStrings AS (
    -- Concatenate a user's top 5 tags into a single string
    SELECT
        utc.OwnerUserId AS UserId,
        STRING_AGG(utc.TagNameCleaned || ' (Score: ' || utc.TagContributionScore || ')', '; ')
            FILTER (WHERE utc.rn_tag_per_user <= 5) AS Top5TagContributions
    FROM UserTopTagContributions utc
    GROUP BY utc.OwnerUserId
),
UserEditSummary AS (
    -- Summarize user's self-edits vs. edits on other users' posts
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) AND p.OwnerUserId = u.Id THEN ph.PostId END) AS SelfEditedPostsCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) AND p.OwnerUserId IS DISTINCT FROM u.Id THEN ph.PostId END) AS OtherEditedPostsCount
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edit Title, Body, Tags
    GROUP BY u.Id
),
UserBadgeSummary AS (
    -- Summarize user badge counts by class and average time to earn them
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(EXTRACT(EPOCH FROM (b.Date - u.CreationDate)) / (60*60*24)) AS AvgDaysToBadge
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    GROUP BY b.UserId
),
UserVoteSummary AS (
    -- Aggregate specific vote types on specific post types for each user
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS UpvotesOnQuestions,
        SUM(CASE WHEN v.VoteTypeId = 3 AND p.PostTypeId = 2 THEN 1 ELSE 0 END) AS DownvotesOnAnswers
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL -- Exclude community posts
    GROUP BY p.OwnerUserId
),
UserTimelineEvents AS (
    -- Consolidate different types of user-related events using UNION ALL
    SELECT
        p.Id AS EventId,
        'PostCreated' AS EventType,
        p.CreationDate AS EventDate,
        p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    UNION ALL
    SELECT
        c.Id AS EventId,
        'CommentCreated' AS EventType,
        c.CreationDate AS EventDate,
        c.UserId AS UserId
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    UNION ALL
    SELECT
        b.Id AS EventId,
        'BadgeAwarded' AS EventType,
        b.Date AS EventDate,
        b.UserId AS UserId
    FROM Badges b
),
UserMonthlyEventCounts AS (
    -- Calculate monthly event counts and cumulative events for each user
    SELECT
        ute.UserId,
        DATE_TRUNC('month', ute.EventDate) AS EventMonth,
        COUNT(ute.EventId) AS MonthlyEventsCount,
        COUNT(DISTINCT ute.EventType) AS DistinctEventTypes,
        -- Window function: Running total of events for the user over time
        SUM(COUNT(ute.EventId)) OVER (PARTITION BY ute.UserId ORDER BY DATE_TRUNC('month', ute.EventDate)) AS UserCumulativeEvents
    FROM UserTimelineEvents ute
    GROUP BY ute.UserId, DATE_TRUNC('month', ute.EventDate)
    HAVING COUNT(ute.EventId) > 5 -- Only months with substantial activity
),
AvgRecentMonthlyEvents AS (
    -- Calculate average monthly events for the last year for each user
    SELECT
        UserId,
        AVG(MonthlyEventsCount) AS AvgMonthlyEventsLastYear
    FROM UserMonthlyEventCounts
    WHERE EventMonth >= DATE_TRUNC('month', cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
    GROUP BY UserId
)
SELECT
    uba.UserId,
    uba.UserName,
    uba.Reputation,
    uba.TotalPosts,
    uba.QuestionCount,
    uba.AnswerCount,
    uba.TotalPostScore,
    uba.TotalComments,
    uba.LatestActivityGlobally,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ROUND(ubs.AvgDaysToBadge, 2), 0.0) AS AvgDaysToBadge,
    upa.BestQuestionId,
    upa.BestQuestionTitle,
    upa.BestQuestionScore,
    upa.BestAnswerId,
    upa.BestAnswerTitle,
    upa.BestAnswerScore,
    COALESCE(upa.Top5QuestionsCount, 0) AS Top5QuestionsCount,
    COALESCE(upa.Top5AnswersCount, 0) AS Top5AnswersCount,
    COALESCE(upa.TotalSelfAcceptedAnswers, 0) AS TotalSelfAcceptedAnswers,
    COALESCE(ues.SelfEditedPostsCount, 0) AS UserSelfEditedPostsCount,
    COALESCE(ues.OtherEditedPostsCount, 0) AS UserOtherEditedPostsCount,
    tut.Top5TagContributions,
    COALESCE(uvs.UpvotesOnQuestions, 0) AS UpvotesOnQuestions,
    COALESCE(uvs.DownvotesOnAnswers, 0) AS DownvotesOnAnswers,
    COALESCE(arme.AvgMonthlyEventsLastYear, 0.0) AS AvgMonthlyEventsLastYear,
    -- Overall average comparisons using window functions on the final result set
    AVG(uba.Reputation) OVER() AS OverallAvgReputation,
    AVG(uba.TotalPosts) OVER() AS OverallAvgPosts,
    -- Complex date calculations and string expressions
    EXTRACT(DAY FROM (cast('2024-10-01 12:34:56' as timestamp) - uba.UserCreationDate)) AS DaysSinceCreation,
    UPPER(LEFT(uba.UserName, 1)) || SUBSTRING(LOWER(uba.UserName), 2) AS FormattedUserName,
    -- Correlated subquery for conditional filtering: checks if any post owned by the user was ever closed
    (SELECT EXISTS (SELECT 1 FROM PostHistory phi WHERE phi.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = uba.UserId) AND phi.PostHistoryTypeId = 10)) AS HasEverClosedOwnedPost,
    -- NULL logic and a complicated expression involving multiple columns to categorize users
    CASE
        WHEN uba.Reputation > 50000 AND COALESCE(ubs.GoldBadges, 0) >= 5 AND COALESCE(ubs.AvgDaysToBadge, 9999) < 365 THEN 'Elite Contributor'
        WHEN uba.Reputation > 10000 AND COALESCE(ubs.SilverBadges, 0) >= 10 THEN 'Experienced Maven'
        WHEN uba.TotalPosts > 100 AND uba.TotalPostScore > 500 AND uba.LatestActivityGlobally > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year') THEN 'Active Participant'
        WHEN uba.QuestionCount = 0 AND uba.AnswerCount > 0 AND uba.TotalPostScore > 100 THEN 'Answer Specialist'
        WHEN uba.TotalPosts > 0 THEN 'General Contributor'
        ELSE 'Lurker / New User'
    END AS UserPersona
FROM UserBaseActivity uba
LEFT JOIN UserBadgeSummary ubs ON uba.UserId = ubs.UserId
LEFT JOIN UserPostAggregates upa ON uba.UserId = upa.UserId
LEFT JOIN UserEditSummary ues ON uba.UserId = ues.UserId
LEFT JOIN UserVoteSummary uvs ON uba.UserId = uvs.UserId
LEFT JOIN TopUserTagStrings tut ON uba.UserId = tut.UserId
LEFT JOIN AvgRecentMonthlyEvents arme ON uba.UserId = arme.UserId
WHERE
    uba.Reputation > 500 AND uba.TotalPosts > 5 AND uba.UserName IS NOT NULL -- Filter for more active and valid users
ORDER BY
    uba.Reputation DESC, uba.LatestActivityGlobally DESC
LIMIT 500;