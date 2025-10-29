-- {"query": "1844.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3072} 

WITH UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE NULL END) AS AvgPostScoreOwned,
        MAX(p.CreationDate) AS LastPostCreationDate,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViewsOnPosts,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswersReceived,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoritesOnPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
),
UserInteractionMetrics AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        AVG(c.Score) AS AvgCommentScoreMade,
        MAX(c.CreationDate) AS LastCommentCreationDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
        COUNT(DISTINCT v.PostId) AS UniquePostsVotedOn,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId ELSE NULL END) AS PostsFavoritedBySelf,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyInitiated
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id
),
PostHistoryAggregates AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(ph.Id) AS HistoryEntryCount,
        AVG(LENGTH(ph.Text)) AS AvgHistoryTextLength,
        MAX(ph.CreationDate) AS LatestHistoryModification,
        LOWER(SUBSTRING(p.Tags FROM POSITION('<' IN p.Tags) + 1 FOR POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1)) AS FirstPostTag,
        (
            SELECT MAX(t.Count) FROM Tags t
            WHERE t.TagName = LOWER(SUBSTRING(p.Tags FROM POSITION('<' IN p.Tags) + 1 FOR POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1))
        ) AS GlobalFirstTagPopularity,
        COUNT(DISTINCT CASE WHEN ph.UserId IS NOT NULL AND ph.UserId != p.OwnerUserId THEN ph.UserId ELSE NULL END) AS ExternalEditorCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2, 4, 5) -- Questions, Answers, TagWikis
    GROUP BY p.Id, p.OwnerUserId, p.Tags
),
UserBadgePerformance AS (
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) AS TotalBadgesAwarded,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(b.Date) AS EarliestBadgeDate,
        MAX(b.Date) AS LatestBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
QuestionAnswerDynamics AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionPostDate,
        q.ViewCount AS QuestionViews,
        q.Score AS QuestionScore,
        COUNT(a.Id) AS AnswerCountForThisQuestion,
        SUM(a.Score) AS TotalAnswerScoreForThisQuestion,
        AVG(LENGTH(a.Body)) AS AvgAnswerBodyLength,
        MAX(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Score ELSE NULL END) AS AcceptedAnswerScore,
        (
            SELECT u_acc.Reputation
            FROM Users u_acc
            WHERE u_acc.Id = acc_a.OwnerUserId
        ) AS AcceptedAnswerOwnerReputation,
        MIN(a.CreationDate) AS FirstAnswerSubmissionDate,
        q.LastActivityDate AS QuestionLastActivity
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2 -- Answers
    LEFT JOIN Posts acc_a ON q.AcceptedAnswerId = acc_a.Id -- Join to get accepted answer details
    WHERE q.PostTypeId = 1 -- Questions only
    GROUP BY q.Id, q.OwnerUserId, q.CreationDate, q.ViewCount, q.Score, q.LastActivityDate, acc_a.OwnerUserId
),
UserPostLinkAnalysis AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT pl.PostId) AS PostsInvolvingLinks,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS OutgoingLinksCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateRelationshipCount,
        COUNT(DISTINCT pl.RelatedPostId) AS UniqueRelatedPosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostLinks pl ON p.Id = pl.PostId
    GROUP BY u.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserRegistrationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views AS ProfileViews,
    u.UpVotes AS UserUpVotesReceived,
    u.DownVotes AS UserDownVotesReceived,
    upa.TotalPostsOwned,
    upa.QuestionsAsked,
    upa.AnswersProvided,
    upa.AvgPostScoreOwned,
    upa.LastPostCreationDate,
    upa.TotalViewsOnPosts,
    upa.TotalAnswersReceived,
    upa.TotalFavoritesOnPosts,
    uim.TotalCommentsMade,
    uim.AvgCommentScoreMade,
    uim.LastCommentCreationDate,
    uim.UpVotesCast,
    uim.DownVotesCast,
    uim.PostsFavoritedBySelf,
    uim.TotalBountyInitiated,
    ubp.TotalBadgesAwarded,
    ubp.GoldBadges,
    ubp.SilverBadges,
    ubp.BronzeBadges,
    ubp.EarliestBadgeDate,
    ubp.LatestBadgeDate,
    upl.PostsInvolvingLinks,
    upl.OutgoingLinksCount,
    upl.DuplicateRelationshipCount,
    upl.UniqueRelatedPosts,
    -- Window functions for ranking and averages
    RANK() OVER (ORDER BY u.Reputation DESC, upa.TotalPostsOwned DESC) AS GlobalReputationRank,
    NTILE(5) OVER (ORDER BY upa.QuestionsAsked DESC, upa.AnswersProvided DESC) AS TopContributorQuintile,
    AVG(upa.AvgPostScoreOwned) OVER (PARTITION BY u.Location) AS AvgReputationByLocation,
    LAG(u.LastAccessDate, 1, u.CreationDate) OVER (ORDER BY u.CreationDate) AS PreviousUserAccessDate, -- Access date of the user created before current user
    COALESCE(lph.HistoryEntryCount, 0) AS LatestPostHistoryEvents,
    COALESCE(lph.AvgHistoryTextLength, 0.0) AS LatestPostAvgHistoryTextLength,
    lph.FirstPostTag AS LatestPostPrimaryTag,
    lph.GlobalFirstTagPopularity AS LatestPostTagGlobalCount,
    lph.ExternalEditorCount AS LatestPostUniqueEditors,
    lqa.AnswerCountForThisQuestion AS RecentQuestionAnswerCount,
    lqa.TotalAnswerScoreForThisQuestion AS RecentQuestionTotalAnswerScore,
    lqa.AcceptedAnswerScore AS RecentQuestionAcceptedAnswerScore,
    lqa.AcceptedAnswerOwnerReputation AS RecentQuestionAcceptedAnswerOwnerRep,
    EXTRACT(EPOCH FROM (lqa.FirstAnswerSubmissionDate - lqa.QuestionPostDate)) / 3600.0 AS TimeToFirstAnswerHours, -- Time difference in hours
    -- Complex expressions and calculations
    (u.Reputation * 0.05 + COALESCE(upa.TotalPostsOwned, 0) * 0.2 + COALESCE(ubp.GoldBadges, 0) * 5 + COALESCE(uim.TotalCommentsMade, 0) * 0.1) AS WeightedEngagementScore,
    -- String manipulations and NULL logic
    COALESCE(REPLACE(REPLACE(u.AboutMe, '<code>', ''), '</code>', ''), 'User has not provided an "About Me" description') AS CleanedAboutMeSummary,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%github.com%' THEN 'GitHub Profile'
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%linkedin.com%' THEN 'LinkedIn Profile'
        WHEN u.WebsiteUrl IS NOT NULL THEN 'Other External Site'
        ELSE 'No Website Specified'
    END AS WebsiteClassification,
    -- Correlated subquery in SELECT for user's first post creation date
    (
        SELECT MIN(p_min.CreationDate)
        FROM Posts p_min
        WHERE p_min.OwnerUserId = u.Id
    ) AS FirstPostDate,
    -- Boolean check for specific user behavior
    CASE
        WHEN u.Reputation > 5000 AND COALESCE(upa.TotalPostsOwned, 0) = 0 THEN TRUE
        ELSE FALSE
    END AS HighReputationNoContent,
    -- Ratio calculation with NULLIF to prevent division by zero
    CAST(COALESCE(upa.TotalAnswersReceived, 0) AS NUMERIC) / NULLIF(COALESCE(upa.QuestionsAsked, 0), 0) AS AnswersPerQuestionRatio
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.UserId
LEFT JOIN UserInteractionMetrics uim ON u.Id = uim.UserId
LEFT JOIN UserBadgePerformance ubp ON u.Id = ubp.UserId
LEFT JOIN UserPostLinkAnalysis upl ON u.Id = upl.UserId
LEFT JOIN ( -- Join to get latest post's history and tag info
    SELECT
        ph.OwnerUserId,
        ph.PostId,
        ph.HistoryEntryCount,
        ph.AvgHistoryTextLength,
        ph.FirstPostTag,
        ph.GlobalFirstTagPopularity,
        ph.ExternalEditorCount,
        ROW_NUMBER() OVER(PARTITION BY ph.OwnerUserId ORDER BY ph.LatestHistoryModification DESC, ph.PostId DESC) AS rn
    FROM PostHistoryAggregates ph
) lph ON u.Id = lph.OwnerUserId AND lph.rn = 1
LEFT JOIN ( -- Join to get info about the user's most recent question
    SELECT
        qa.QuestionOwnerId,
        qa.QuestionId,
        qa.QuestionPostDate,
        qa.QuestionViews,
        qa.QuestionScore,
        qa.AnswerCountForThisQuestion,
        qa.TotalAnswerScoreForThisQuestion,
        qa.AvgAnswerBodyLength,
        qa.AcceptedAnswerScore,
        qa.AcceptedAnswerOwnerReputation,
        qa.FirstAnswerSubmissionDate,
        qa.QuestionLastActivity,
        ROW_NUMBER() OVER(PARTITION BY qa.QuestionOwnerId ORDER BY qa.QuestionPostDate DESC) AS rn
    FROM QuestionAnswerDynamics qa
) lqa ON u.Id = lqa.QuestionOwnerId AND lqa.rn = 1
WHERE
    u.Reputation >= 1000
    AND u.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    AND (u.Location IS NOT NULL AND u.Location ILIKE '%london%' OR u.Location ILIKE '%new york%') -- Complex location filter
    AND (
        upa.QuestionsAsked > 5
        OR uim.TotalCommentsMade > 20
        OR ubp.GoldBadges > 0
    )
    AND NOT EXISTS ( -- Exclude users who have been involved in more than 2 post deletions
        SELECT 1
        FROM PostHistory ph_del
        WHERE ph_del.UserId = u.Id
          AND ph_del.PostHistoryTypeId = 12 -- Post Deleted
        GROUP BY ph_del.UserId
        HAVING COUNT(ph_del.Id) > 2
    )
ORDER BY
    GlobalReputationRank ASC,
    WeightedEngagementScore DESC,
    lqa.QuestionLastActivity DESC NULLS LAST
LIMIT 750;
