-- {"query": "49024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1693} 

WITH UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AveragePostScore,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL AND p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AnswersAcceptedByOthers,
        SUM(p.ViewCount) AS TotalPostViews,
        SUM(p.FavoriteCount) AS TotalFavoriteCounts,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    LEFT JOIN Posts q ON p.ParentId = q.Id AND p.PostTypeId = 2 -- Link answers to questions
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserHistoryStats AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Edit Title, Edit Body, Edit Tags
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS CloseDeleteCount, -- Post Closed or Post Deleted
        SUM(CASE WHEN ph.PostHistoryTypeId IN (11, 13) THEN 1 ELSE 0 END) AS ReopenUndeleteCount -- Post Reopened or Post Undeleted
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
PopularTags AS (
    SELECT
        TRIM(unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(p.Score) AS TotalTagScore,
        AVG(p.Score) AS AverageTagScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY TagName
    HAVING COUNT(DISTINCT p.Id) > 500 AND SUM(p.Score) > 1000
),
UserPopularTagParticipation AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT pt.TagName) AS UniquePopularTagsContributed,
        SUM(pt.TotalTagScore) AS TotalPopularTagInfluence,
        AVG(pt.AverageTagScore) AS AveragePopularTagEngagement
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS user_tag(TagName) ON p.PostTypeId = 1 AND p.Tags IS NOT NULL
    JOIN PopularTags pt ON user_tag.TagName = pt.TagName
    GROUP BY u.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(ups.TotalPosts, 0) AS TotalPosts,
    COALESCE(ups.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(ups.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ups.AveragePostScore, 0.0) AS AverageOverallPostScore,
    COALESCE(ups.QuestionsWithAcceptedAnswers, 0) AS QuestionsWithAcceptedAnswersByOthers,
    COALESCE(ups.AnswersAcceptedByOthers, 0) AS AnswersAcceptedByOthers,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(uhs.EditCount, 0) AS TotalEditsMade,
    COALESCE(uhs.CloseDeleteCount, 0) AS PostsClosedOrDeleted,
    COALESCE(uptp.UniquePopularTagsContributed, 0) AS PopularTagsContributedCount,
    COALESCE(uptp.TotalPopularTagInfluence, 0) AS TotalPopularTagScoreInfluence,
    COALESCE(uptp.AveragePopularTagEngagement, 0.0) AS AveragePopularTagEngagementScore,
    DENSE_RANK() OVER (
        ORDER BY
            u.Reputation DESC,
            COALESCE(ups.TotalPosts, 0) DESC,
            COALESCE(ups.AnswersAcceptedByOthers, 0) DESC,
            COALESCE(ubs.GoldBadges, 0) DESC,
            COALESCE(uptp.TotalPopularTagInfluence, 0) DESC
    ) AS OverallActivityRank,
    NTILE(5) OVER (ORDER BY u.Reputation DESC) AS ReputationQuintile,
    DATE_PART('day', AGE(u.LastAccessDate, u.CreationDate)) AS DaysActiveSinceCreation,
    (SELECT COUNT(DISTINCT c.PostId) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate > u.LastAccessDate - INTERVAL '1 year') AS UniquePostsCommentedLastYear,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8 AND v.CreationDate > u.LastAccessDate - INTERVAL '2 years') AS AverageBountyStartedInLastTwoYears,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) AS PreviousUserReputation
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN UserHistoryStats uhs ON u.Id = uhs.UserId
LEFT JOIN UserPopularTagParticipation uptp ON u.Id = uptp.UserId
WHERE
    u.Reputation > 5000 AND
    u.Views > 100 AND
    COALESCE(ups.TotalPosts, 0) > 20 AND
    COALESCE(ups.AnswersAcceptedByOthers, 0) > 5 AND
    COALESCE(uptp.UniquePopularTagsContributed, 0) > 2 AND
    u.CreationDate < '2022-01-01'
ORDER BY
    OverallActivityRank ASC,
    u.LastAccessDate DESC,
    u.Id ASC
LIMIT 2000;
