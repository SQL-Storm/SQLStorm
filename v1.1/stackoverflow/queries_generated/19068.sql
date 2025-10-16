-- {"query": "19068.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2760} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.DisplayName,
        u.Location,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId IN (4, 5) THEN 1 ELSE 0 END) AS TotalTagWikis,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViewsReceived,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalPostFavoritesReceived,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        MAX(CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 1 ELSE 0 END) AS HasDetailedAboutMe,
        u.AboutMe
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.DisplayName, u.Location,
        u.Views, u.UpVotes, u.DownVotes, u.AboutMe
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        p.CommunityOwnedDate,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT MAX(ph.CreationDate)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
         AND ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Edit types
        ) AS LastEditDateFromHistory,
        (SELECT ph.Comment
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
         AND ph.PostHistoryTypeId = 10 -- Post Closed
         ORDER BY ph.CreationDate DESC
         LIMIT 1
        ) AS LastCloseReasonComment,
        LENGTH(COALESCE(p.Title, '')) AS TitleLength,
        LENGTH(REGEXP_REPLACE(p.Body, '<[^>]+>', '', 'g')) AS BodyTextLength, -- Stripping HTML tags for text length
        (SELECT pl.RelatedPostId
         FROM PostLinks pl
         WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate
         ORDER BY pl.CreationDate DESC
         LIMIT 1
        ) AS DuplicateOfPostId
    FROM Posts p
),
TagAnalysis AS (
    SELECT
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 -- Only analyze tags for questions
),
AggregatedTagStats AS (
    SELECT
        ta.TagName,
        COUNT(DISTINCT ta.PostId) AS QuestionsWithTag,
        AVG(pm.PostScore) AS AvgScoreForTagQuestions,
        COUNT(DISTINCT pm.OwnerUserId) AS UniqueUsersUsingTag,
        AVG(pm.ViewCount) AS AvgViewCountForTagQuestions
    FROM TagAnalysis ta
    JOIN PostMetrics pm ON ta.PostId = pm.PostId
    GROUP BY ta.TagName
),
RankedTagPerformance AS (
    SELECT
        ats.TagName,
        ats.QuestionsWithTag,
        ats.AvgScoreForTagQuestions,
        ats.UniqueUsersUsingTag,
        ats.AvgViewCountForTagQuestions,
        RANK() OVER (ORDER BY ats.QuestionsWithTag DESC, ats.AvgScoreForTagQuestions DESC) AS TagQuestionRank,
        NTILE(4) OVER (ORDER BY ats.AvgViewCountForTagQuestions DESC) AS ViewCountQuartile
    FROM AggregatedTagStats ats
    WHERE ats.QuestionsWithTag >= 10 -- Only consider tags with at least 10 questions
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.Location,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalCommentsMade,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    COALESCE(uas.TotalPostScoreReceived * 1.0 / NULLIF(uas.TotalPosts, 0), 0) AS AvgScorePerPost,
    COALESCE(uas.TotalPostViewsReceived * 1.0 / NULLIF(uas.TotalPosts, 0), 0) AS AvgViewsPerPost,
    COALESCE(uas.TotalQuestions * 1.0 / NULLIF(EXTRACT(EPOCH FROM (uas.LastAccessDate - uas.UserCreationDate)) / (3600 * 24), 0), 0) AS QuestionsPerDaySinceAccess,
    MAX(CASE WHEN pm.PostTypeId = 1 AND pm.ClosedDate IS NULL AND pm.PostScore >= 5 AND pm.AnswerCount = 0 THEN 1 ELSE 0 END) AS HasOpenHighScoreUnansweredQuestion,
    COUNT(DISTINCT CASE WHEN pm.PostTypeId = 1 AND pm.PostScore > 100 AND pm.AnswerCount > 0 THEN pm.PostId END) AS HighScoreAnsweredQuestionsCount,
    AVG(pm.BodyTextLength) FILTER (WHERE pm.PostTypeId = 1) AS AvgQuestionBodyLength,
    AVG(pm.BodyTextLength) FILTER (WHERE pm.PostTypeId = 2) AS AvgAnswerBodyLength,
    SUM(pm.UpVoteCount) AS TotalUpvotesOnUserPosts,
    SUM(pm.DownVoteCount) AS TotalDownvotesOnUserPosts,
    -- Window functions
    RANK() OVER (PARTITION BY COALESCE(uas.Location, 'Unknown') ORDER BY uas.Reputation DESC) AS RankInLocation,
    NTILE(10) OVER (ORDER BY uas.TotalPostScoreReceived DESC) AS ScoreDecile,
    AVG(pm.PostScore) OVER (PARTITION BY uas.UserId ORDER BY pm.PostCreationDate ASC ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreLast4,
    LAG(pm.PostScore, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY pm.PostCreationDate) AS PrevPostScore,
    -- Correlated subquery checks
    CASE
        WHEN EXISTS (
            SELECT 1 FROM Posts p_inner
            WHERE p_inner.OwnerUserId = uas.UserId
            AND p_inner.CreationDate >= (NOW() - INTERVAL '30 days')
            AND p_inner.Score >= 5
        ) THEN 'Recently Active & Highly Rated'
        ELSE 'Less Recent or Lower Rated'
    END AS RecentActivityStatus,
    -- String expressions
    (LOWER(uas.DisplayName) LIKE '%admin%' OR LOWER(uas.DisplayName) LIKE '%moderator%') AS IsAdminOrModeratorNameGuess,
    (REPLACE(REPLACE(REPLACE(uas.AboutMe, '<b>', ''), '</b>', ''), '<i>', '') LIKE '%database%'
     OR REPLACE(REPLACE(REPLACE(uas.AboutMe, '<b>', ''), '</b>', ''), '<i>', '') LIKE '%sql%') AS AboutMeMentionsTechKeyword,
    -- NULL logic and complicated predicates
    COALESCE(uas.Location, 'Unknown') AS UserLocation,
    (NULLIF(uas.TotalQuestions, 0) IS NULL) AS HasNoQuestions,
    SUM(CASE WHEN pm.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedPosts,
    SUM(CASE WHEN pm.ClosedDate IS NOT NULL AND pm.LastCloseReasonComment LIKE '101%' THEN 1 ELSE 0 END) AS TotalDuplicateClosedPosts, -- '101' is a common CloseReasonType Id for Duplicate
    SUM(CASE WHEN pm.DuplicateOfPostId IS NOT NULL THEN 1 ELSE 0 END) AS TotalPostsMarkedAsDuplicate,
    SUM(CASE WHEN pm.PostTypeId = 2 AND pm.ParentId IS NOT NULL AND pm.PostCreationDate < (SELECT q.CreationDate FROM Posts q WHERE q.Id = pm.ParentId) THEN 1 ELSE 0 END) AS AnswersBeforeQuestionCreation,
    -- Joining with RankedTagPerformance for tag insights
    ARRAY_AGG(DISTINCT rtp.TagName ORDER BY rtp.TagQuestionRank ASC) FILTER (WHERE rtp.TagQuestionRank <= 10) AS TopTagsAssociated
FROM UserActivitySummary uas
LEFT JOIN PostMetrics pm ON uas.UserId = pm.OwnerUserId
LEFT JOIN LATERAL ( -- Lateral join to handle unnesting and tag association efficiently
    SELECT ta.TagName
    FROM TagAnalysis ta
    WHERE ta.PostId = pm.PostId
) AS post_tags ON TRUE
LEFT JOIN RankedTagPerformance rtp ON post_tags.TagName = rtp.TagName
WHERE
    uas.Reputation > 1000
    AND uas.LastAccessDate >= (NOW() - INTERVAL '6 months') -- Active users in the last 6 months
    AND uas.TotalPosts > 0
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.Location, uas.UserCreationDate, uas.LastAccessDate,
    uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers, uas.TotalCommentsMade,
    uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges, uas.TotalPostScoreReceived, uas.TotalPostViewsReceived,
    uas.HasDetailedAboutMe, uas.AboutMe -- Group by all non-aggregated/non-window function selected columns
HAVING
    COUNT(CASE WHEN pm.PostTypeId = 1 THEN pm.PostId END) > 5 -- Users with at least 5 questions
    AND (
        COALESCE(SUM(pm.UpVoteCount), 0) > COALESCE(SUM(pm.DownVoteCount), 0) * 1.5 -- More upvotes than downvotes ratio
        OR uas.GoldBadges > 0 -- Or has gold badges
    )
ORDER BY
    uas.Reputation DESC, uas.LastAccessDate DESC
LIMIT 100;
