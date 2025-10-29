-- {"query": "1061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3961} 
WITH HotQuestions AS (
    -- Identifies 'hot' questions based on score, view count, recent activity, specific tags, and open status.
    -- Calculates a composite 'HotnessMetric'.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.CreationDate,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COALESCE(ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1), 0) AS TagCount,
        -- Complex hotness calculation: weighted score, views, favorites, answers, with a slight age penalty.
        (p.Score * 0.75) + (p.ViewCount * 0.005) + (COALESCE(p.FavoriteCount, 0) * 1.2)
        + (CASE WHEN p.AnswerCount > 0 THEN p.AnswerCount * 0.5 ELSE 0 END)
        + (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)) / 86400.0) * -0.01
        AS HotnessMetric
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.Score >= 5
        AND p.ViewCount >= 50
        AND p.LastActivityDate >= (CURRENT_TIMESTAMP - INTERVAL '9 months')
        AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%' OR p.Tags LIKE '%<performance>%')
        AND p.ClosedDate IS NULL -- Only open questions
),
UserPostStats AS (
    -- Aggregates various post-related statistics for each user.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreOnOwnedPosts,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountOnOwnedPosts,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScoreOwned,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScoreOwned,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsOwned,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersOwned,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        -- Check if an answer owned by the user was accepted for its parent question.
        SUM(CASE WHEN p.PostTypeId = 2 AND p_q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersReceived
    FROM
        Posts p
    LEFT JOIN Posts p_q ON p.PostTypeId = 2 AND p.ParentId = p_q.Id -- Join to parent question for accepted answer check
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
PostEngagementMetrics AS (
    -- Calculates detailed engagement metrics per post, including comment counts, vote counts, and upvote ratios.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount,
        CAST(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(
            CAST(SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS DECIMAL), 0
        ) AS UpvoteToTotalVoteRatio
    FROM
        Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY
        p.Id, p.OwnerUserId
),
PostEngagementMetricsAggregated AS (
    -- Aggregates post engagement metrics to a per-user basis.
    SELECT
        pem.OwnerUserId AS UserId,
        SUM(pem.CommentCount) AS TotalCommentCount,
        SUM(pem.UpVoteCount) AS TotalUpVoteCount,
        SUM(pem.DownVoteCount) AS TotalDownVoteCount,
        AVG(pem.UpvoteToTotalVoteRatio) FILTER (WHERE pem.UpvoteToTotalVoteRatio IS NOT NULL) AS AverageUpvoteRatio
    FROM
        PostEngagementMetrics pem
    WHERE pem.OwnerUserId IS NOT NULL
    GROUP BY
        pem.OwnerUserId
),
DuplicatePostInfo AS (
    -- Identifies posts that are duplicates based on PostLinks or PostHistory close reasons, including parsing JSON for original IDs.
    SELECT
        p.Id AS PostId,
        MAX(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsDirectlyLinkedAsDuplicate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('1', '101') THEN 1 ELSE 0 END) AS WasClosedAsDuplicateInHistory,
        -- Extracts original duplicate question IDs from JSON in PostHistory.Text.
        ARRAY_AGG(DISTINCT JSONB_ARRAY_ELEMENTS_TEXT(ph.Text::jsonb -> 'OriginalQuestionIds')) FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IN ('1', '101') AND ph.Text IS NOT NULL)::text[] AS OriginalDuplicateQuestions
    FROM
        Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 -- Only for questions
    GROUP BY
        p.Id
),
DuplicatePostsAggregated AS (
    -- Aggregates duplicate post information to a per-user basis.
    SELECT
        p.OwnerUserId AS UserId,
        MAX(COALESCE(dpi.IsDirectlyLinkedAsDuplicate, 0)) AS HasDirectlyLinkedDuplicates,
        MAX(COALESCE(dpi.WasClosedAsDuplicateInHistory, 0)) AS HasBeenClosedAsDuplicate
    FROM
        Posts p
    INNER JOIN DuplicatePostInfo dpi ON p.Id = dpi.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
HistoricalAnswerPerformance AS (
    -- Calculates ranking and score deviation for answers within their respective questions using window functions.
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankByScore,
        AVG(a.Score) OVER (PARTITION BY a.ParentId) AS AvgAnswerScoreForQuestion,
        COUNT(a.Id) OVER (PARTITION BY a.ParentId) AS TotalAnswersForQuestion,
        (a.Score - AVG(a.Score) OVER (PARTITION BY a.ParentId)) AS ScoreDeviationFromAvg
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2 -- Only answers
        AND a.ParentId IS NOT NULL
),
HistoricalAnswerPerformanceAggregated AS (
    -- Aggregates historical answer performance to a per-user basis.
    SELECT
        hap.AnswerOwnerId AS UserId,
        AVG(hap.AnswerScore) AS AverageAnswerScoreGiven,
        AVG(hap.AnswerRankByScore) AS AverageAnswerRankGiven,
        AVG(hap.ScoreDeviationFromAvg) AS AverageScoreDeviation
    FROM
        HistoricalAnswerPerformance hap
    WHERE hap.AnswerOwnerId IS NOT NULL
    GROUP BY
        hap.AnswerOwnerId
),
UserBadgeSummary AS (
    -- Summarizes badge counts by class for each user.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Badges b
    GROUP BY
        b.UserId
)
SELECT
    U.Id AS UserId,
    COALESCE(U.DisplayName, 'Unknown User') AS DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    COALESCE(UPS.QuestionsOwned, 0) AS TotalQuestionsPosted,
    COALESCE(UPS.AnswersOwned, 0) AS TotalAnswersPosted,
    COALESCE(UPS.AcceptedAnswersReceived, 0) AS AcceptedAnswersCount,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadgesCount,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesCount,
    SUM(COALESCE(HQ.HotnessMetric, 0)) AS TotalHotQuestionContributionScore,
    COUNT(DISTINCT HQ.PostId) AS NumberOfHotQuestionsInvolved, -- Questions owned or whose accepted answer is owned by the user
    COALESCE(HAPA.AverageAnswerScoreGiven, 0.0) AS AverageAnswerScoreGiven,
    COALESCE(HAPA.AverageAnswerRankGiven, 0.0) AS AverageAnswerRankGiven,
    COALESCE(DPA.HasDirectlyLinkedDuplicates, 0) AS HasDirectlyLinkedDuplicatesFlag,
    COALESCE(DPA.HasBeenClosedAsDuplicate, 0) AS HasBeenClosedAsDuplicateFlag,
    COALESCE(PEM_AGG.TotalCommentCount, 0) AS TotalCommentsOnOwnPosts,
    COALESCE(PEM_AGG.TotalUpVoteCount, 0) AS TotalUpVotesOnOwnPosts,
    COALESCE(PEM_AGG.TotalDownVoteCount, 0) AS TotalDownVotesOnOwnPosts,
    COALESCE(PEM_AGG.AverageUpvoteRatio, 0.0) AS AverageUpvoteRatioOnOwnPosts,
    -- Ranks users into 5 percentiles based on combined performance metrics.
    NTILE(5) OVER (
        ORDER BY
            U.Reputation DESC,
            SUM(COALESCE(HQ.HotnessMetric, 0)) DESC,
            COALESCE(UBS.GoldBadges, 0) DESC,
            COALESCE(UPS.AcceptedAnswersReceived, 0) DESC
    ) AS UserEngagementPercentileRank,
    -- A comprehensive score combining various user contributions and activity metrics, with bonuses and penalties.
    (
        U.Reputation * 0.3
        + COALESCE(UBS.GoldBadges, 0) * 120
        + COALESCE(UBS.SilverBadges, 0) * 25
        + COALESCE(UPS.AcceptedAnswersReceived, 0) * 60
        + SUM(COALESCE(HQ.HotnessMetric, 0)) * 0.15
        + (CASE WHEN (CURRENT_TIMESTAMP - U.CreationDate) < INTERVAL '1 year' THEN 75 ELSE 0 END) -- Bonus for new active users
        - (CASE WHEN (CURRENT_TIMESTAMP - U.LastAccessDate) > INTERVAL '6 months' THEN 30 ELSE 0 END) -- Penalty for inactive users
        - (COALESCE(DPA.HasBeenClosedAsDuplicate, 0) * 15) -- Penalty for duplicates
        + COALESCE(UPS.AvgQuestionScoreOwned, 0) * 0.7
        + COALESCE(UPS.AvgAnswerScoreOwned, 0) * 0.9
        + COALESCE(HAPA.AverageScoreDeviation, 0) * 0.5 -- Reward/penalize for answer performance relative to others
    ) AS CalculatedUserImpactScore,
    -- Formats the 'AboutMe' text, truncating if too long, handling NULLs.
    COALESCE(
        CASE
            WHEN LENGTH(U.AboutMe) > 150 THEN SUBSTRING(U.AboutMe, 1, 150) || '...'
            ELSE U.AboutMe
        END,
        'No "About Me" information.'
    ) AS FormattedAboutMe,
    -- Correlated Subquery: Checks if the user has any recent (last year) posts (questions or answers) with zero comments, and are still open/not community-owned.
    EXISTS (
        SELECT 1
        FROM Posts p_no_comments
        WHERE p_no_comments.OwnerUserId = U.Id
          AND p_no_comments.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
          AND p_no_comments.CommentCount = 0
          AND p_no_comments.ClosedDate IS NULL
          AND p_no_comments.CommunityOwnedDate IS NULL
        LIMIT 1
    ) AS HasRecentZeroCommentPosts,
    -- Correlated Subquery: Checks if any of the user's questions were closed as "Off-topic" in the last two years.
    EXISTS (
        SELECT 1
        FROM PostHistory ph_off_topic
        INNER JOIN Posts p_q_off_topic ON ph_off_topic.PostId = p_q_off_topic.Id
        WHERE p_q_off_topic.OwnerUserId = U.Id
          AND ph_off_topic.PostHistoryTypeId = 10 -- Post Closed
          AND ph_off_topic.Comment IN ('2', '102') -- Off-topic close reasons
          AND ph_off_topic.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2 years')
        LIMIT 1
    ) AS HasRecentOffTopicCloseHistory
FROM
    Users U
LEFT JOIN UserPostStats UPS ON U.Id = UPS.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
-- Join for hot questions: User either owns the hot question OR owns the accepted answer for a hot question.
LEFT JOIN HotQuestions HQ ON U.Id = HQ.OwnerUserId OR (U.Id = (SELECT pa.OwnerUserId FROM Posts pa WHERE pa.Id = HQ.AcceptedAnswerId AND pa.PostTypeId = 2))
LEFT JOIN HistoricalAnswerPerformanceAggregated HAPA ON U.Id = HAPA.UserId
LEFT JOIN DuplicatePostsAggregated DPA ON U.Id = DPA.UserId
LEFT JOIN PostEngagementMetricsAggregated PEM_AGG ON U.Id = PEM_AGG.UserId
WHERE
    U.Reputation > 500 -- Filters for more established users with minimum reputation.
    AND U.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year') -- Ensures users are somewhat recently active.
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.AboutMe,
    COALESCE(UPS.QuestionsOwned, 0), COALESCE(UPS.AnswersOwned, 0), COALESCE(UPS.AcceptedAnswersReceived, 0),
    COALESCE(UBS.TotalBadges, 0), COALESCE(UBS.GoldBadges, 0), COALESCE(UBS.SilverBadges, 0),
    COALESCE(HAPA.AverageAnswerScoreGiven, 0.0), COALESCE(HAPA.AverageAnswerRankGiven, 0.0),
    COALESCE(DPA.HasDirectlyLinkedDuplicates, 0), COALESCE(DPA.HasBeenClosedAsDuplicate, 0),
    COALESCE(PEM_AGG.TotalCommentCount, 0), COALESCE(PEM_AGG.TotalUpVoteCount, 0),
    COALESCE(PEM_AGG.TotalDownVoteCount, 0), COALESCE(PEM_AGG.AverageUpvoteRatio, 0.0),
    COALESCE(UPS.AvgQuestionScoreOwned, 0), COALESCE(UPS.AvgAnswerScoreOwned, 0), COALESCE(HAPA.AverageScoreDeviation, 0)
HAVING
    SUM(COALESCE(HQ.HotnessMetric, 0)) > 50 -- Ensures significant contribution to hot questions.
    OR COALESCE(UBS.GoldBadges, 0) > 0 -- Or has earned at least one gold badge.
    OR COALESCE(UPS.AcceptedAnswersReceived, 0) > 5 -- Or has a notable number of accepted answers.
ORDER BY
    CalculatedUserImpactScore DESC, U.Reputation DESC
LIMIT 200;