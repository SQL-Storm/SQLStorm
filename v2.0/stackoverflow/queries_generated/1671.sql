-- {"query": "1671.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3442} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalPostViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore, -- Handle NULL scores for comments
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Location, u.UpVotes, u.DownVotes
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS TagName
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL
),
AggregatedTagStats AS (
    SELECT
        pta.TagName,
        COUNT(DISTINCT pta.PostId) AS TaggedPostsCount,
        SUM(pta.Score) AS TagTotalScore,
        SUM(pta.ViewCount) AS TagTotalViewCount,
        AVG(CAST(pta.Score AS NUMERIC)) AS TagAverageScore
    FROM PostTagAnalysis AS pta
    GROUP BY pta.TagName
    HAVING COUNT(DISTINCT pta.PostId) > 100 -- Filter for reasonably popular tags
),
UserTagContributions AS (
    SELECT
        pta.OwnerUserId AS UserId,
        pta.TagName,
        COUNT(pta.PostId) AS UserPostsInTag,
        SUM(pta.Score) AS UserScoreInTag,
        AVG(CAST(pta.Score AS NUMERIC)) AS UserAvgScoreInTag,
        RANK() OVER (PARTITION BY pta.TagName ORDER BY SUM(pta.Score) DESC, COUNT(pta.PostId) DESC) AS UserRankInTag
    FROM PostTagAnalysis AS pta
    WHERE pta.OwnerUserId IS NOT NULL
    GROUP BY pta.OwnerUserId, pta.TagName
),
PostEditActivity AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.RevisionGUID) AS TotalRevisions,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        MAX(ph.CreationDate) AS LastEditDateHistory,
        MIN(ph.CreationDate) AS FirstEditDateHistory,
        ARRAY_AGG(DISTINCT ph.PostHistoryTypeId ORDER BY ph.PostHistoryTypeId) AS HistoryTypeIds
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit Title, Edit Body, Edit Tags, Rollback Body
    GROUP BY ph.PostId
),
QuestionAnswerPerformance AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN TRUE ELSE FALSE END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankByScore
    FROM Posts AS q
    JOIN Posts AS a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
QuestionAcceptanceRateByUser AS (
    SELECT
        qap.AnswerOwnerId AS UserId,
        COUNT(qap.AnswerId) AS TotalAnswersProvided,
        SUM(CASE WHEN qap.IsAcceptedAnswer THEN 1 ELSE 0 END) AS AcceptedAnswersProvided
    FROM QuestionAnswerPerformance AS qap
    WHERE qap.AnswerOwnerId IS NOT NULL
    GROUP BY qap.AnswerOwnerId
),
QuestionOwnerAcceptanceMetrics AS (
    SELECT
        qap.QuestionOwnerId AS UserId,
        COUNT(qap.QuestionId) AS TotalQuestionsAskedWithAnswers,
        SUM(CASE WHEN qap.IsAcceptedAnswer THEN 1 ELSE 0 END) AS QuestionsAcceptedAnswered
    FROM QuestionAnswerPerformance AS qap
    WHERE qap.QuestionOwnerId IS NOT NULL
    GROUP BY qap.QuestionOwnerId
),
PostEditSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pe.PostId) FILTER (WHERE pe.TotalRevisions IS NOT NULL) AS PostsWithEditsCount,
        MAX(pe.TotalRevisions) AS MaxPostRevisions,
        AVG(CAST(pe.TotalRevisions AS NUMERIC)) AS AvgPostRevisions,
        AVG(CAST(pe.UniqueEditors AS NUMERIC)) AS AvgUniqueEditorsPerPost,
        SUM(CASE WHEN EXISTS (SELECT 1 FROM UNNEST(pe.HistoryTypeIds) AS htid WHERE htid = 4) THEN 1 ELSE 0 END) AS TitleEditCount,
        SUM(CASE WHEN EXISTS (SELECT 1 FROM UNNEST(pe.HistoryTypeIds) AS htid WHERE htid = 5) THEN 1 ELSE 0 END) AS BodyEditCount
    FROM Posts AS p
    JOIN PostEditActivity AS pe ON p.Id = pe.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
PostLinkSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pl_link.RelatedPostId) AS OutgoingLinksCount,
        COUNT(DISTINCT pl_dup.RelatedPostId) AS DuplicateLinksCount,
        COUNT(DISTINCT pl_link_inv.PostId) AS IncomingLinksCount,
        COUNT(DISTINCT pl_dup_inv.PostId) AS IncomingDuplicateLinksCount
    FROM Posts AS p
    LEFT JOIN PostLinks AS pl_link ON p.Id = pl_link.PostId AND pl_link.LinkTypeId = 1 -- Linked FROM p
    LEFT JOIN PostLinks AS pl_dup ON p.Id = pl_dup.PostId AND pl_dup.LinkTypeId = 3 -- Duplicate FROM p
    LEFT JOIN PostLinks AS pl_link_inv ON p.Id = pl_link_inv.RelatedPostId AND pl_link_inv.LinkTypeId = 1 -- Linked TO p
    LEFT JOIN PostLinks AS pl_dup_inv ON p.Id = pl_dup_inv.RelatedPostId AND pl_dup_inv.LinkTypeId = 3 -- Duplicate TO p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserPostDateMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        MIN(EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate)) / 3600 / 24) FILTER (WHERE p.LastEditDate IS NOT NULL AND p.PostTypeId = 1) AS MinDaysToFirstEditQuestion,
        MAX(EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate)) / 3600 / 24) FILTER (WHERE p.LastEditDate IS NOT NULL AND p.PostTypeId = 2) AS MaxDaysToFirstEditAnswer,
        SUM(CASE WHEN LENGTH(p.Body) > 1000 AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS LongQuestionCount,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS ClosedQuestionCount,
        SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedPostCount
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserTagEngagementSummary AS (
    SELECT
        utc.UserId,
        ARRAY_TO_STRING(ARRAY_AGG(DISTINCT utc.TagName ORDER BY utc.TagName), ', ') AS TopTagsUserContributed,
        SUM(utc.UserPostsInTag) AS TotalUserPostsInTags,
        SUM(utc.UserScoreInTag) AS TotalUserScoreInTags,
        AVG(utc.UserAvgScoreInTag) AS AvgUserAvgScoreAcrossTags
    FROM UserTagContributions AS utc
    JOIN AggregatedTagStats AS ats ON utc.TagName = ats.TagName
    WHERE utc.UserRankInTag <= 10 -- Consider top 10 contributions per tag
    GROUP BY utc.UserId
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.Location,
    ues.TotalPosts,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.TotalPostScore,
    ues.TotalCommentsMade,
    ues.GoldBadges,
    ues.SilverBadges,
    ues.BronzeBadges,
    COALESCE(ROUND(CAST(qoam.QuestionsAcceptedAnswered AS NUMERIC) / NULLIF(qoam.TotalQuestionsAskedWithAnswers, 0) * 100, 2), 0) AS AcceptanceRateForOwnQuestions,
    COALESCE(ROUND(CAST(qarb.AcceptedAnswersProvided AS NUMERIC) / NULLIF(qarb.TotalAnswersProvided, 0) * 100, 2), 0) AS AcceptanceRateForProvidedAnswers,
    utes.TopTagsUserContributed,
    utes.TotalUserPostsInTags,
    pes.MaxPostRevisions,
    pes.AvgUniqueEditorsPerPost,
    pls.OutgoingLinksCount,
    pls.IncomingLinksCount,
    updm.MinDaysToFirstEditQuestion,
    updm.MaxDaysToFirstEditAnswer,
    updm.LongQuestionCount,
    updm.ClosedQuestionCount,
    updm.CommunityOwnedPostCount,
    COALESCE(u.WebsiteUrl, 'No Website Provided') AS UserWebsiteStatus,
    NTILE(5) OVER (ORDER BY ues.Reputation DESC, ues.TotalPostScore DESC) AS ReputationTier,
    RANK() OVER (PARTITION BY LEFT(COALESCE(ues.DisplayName, '')) ORDER BY ues.Reputation DESC, ues.TotalPostScore DESC) AS RankInDisplayNameGroup,
    (SELECT AVG(p_sub.Score)
     FROM Posts AS p_sub
     WHERE p_sub.OwnerUserId = ues.UserId
       AND p_sub.CreationDate BETWEEN ues.CreationDate AND ues.LastAccessDate
       AND p_sub.PostTypeId IN (1, 2)
       AND p_sub.Body ILIKE '%exception%' -- Correlated subquery example with different string search
    ) AS AvgScoreForExceptionPosts,
    (SELECT COUNT(DISTINCT v_sub.PostId)
     FROM Votes AS v_sub
     WHERE v_sub.UserId = ues.UserId AND v_sub.VoteTypeId = 5 -- Favorite votes
       AND v_sub.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    ) AS RecentFavoriteVotesGiven,
    CASE
        WHEN ues.Reputation >= 100000 AND ues.GoldBadges >= 5 AND COALESCE(updm.ClosedQuestionCount, 0) = 0 THEN 'Legendary Contributor (Flawless)'
        WHEN ues.Reputation >= 50000 AND ues.SilverBadges >= 10 AND COALESCE(pls.OutgoingLinksCount, 0) > 20 THEN 'Senior Influencer (Networked)'
        WHEN ues.Reputation >= 10000 AND ues.TotalPosts >= 100 AND COALESCE(pes.AvgPostRevisions, 0) > 1.5 THEN 'Active Community Member (Refiner)'
        ELSE 'Emerging Contributor'
    END AS UserContributionTier
FROM UserEngagementSummary AS ues
LEFT JOIN Users AS u ON ues.UserId = u.Id
LEFT JOIN QuestionAcceptanceRateByUser AS qarb ON ues.UserId = qarb.UserId
LEFT JOIN QuestionOwnerAcceptanceMetrics AS qoam ON ues.UserId = qoam.UserId
LEFT JOIN UserTagEngagementSummary AS utes ON ues.UserId = utes.UserId
LEFT JOIN PostEditSummary AS pes ON ues.UserId = pes.UserId
LEFT JOIN PostLinkSummary AS pls ON ues.UserId = pls.UserId
LEFT JOIN UserPostDateMetrics AS updm ON ues.UserId = updm.UserId
WHERE
    ues.Reputation > 5000
    AND ues.TotalPosts > 50
    AND ues.LastAccessDate >= CURRENT_DATE - INTERVAL '6 months'
    AND ues.DisplayName IS NOT NULL
    AND ues.Location IS NOT NULL
    AND ues.Location NOT ILIKE '%mars%' -- Exclude fictional locations
    AND EXISTS (
        SELECT 1
        FROM Badges AS b_sub
        WHERE b_sub.UserId = ues.UserId
          AND b_sub.Class IN (1, 2) -- Gold or Silver
          AND b_sub.Date >= CURRENT_DATE - INTERVAL '3 years'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory AS ph_sub
        WHERE ph_sub.UserId = ues.UserId
          AND ph_sub.PostHistoryTypeId IN (12, 14) -- Post Deleted, Post Locked
          AND ph_sub.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    )
ORDER BY ues.Reputation DESC, ues.TotalPostScore DESC
LIMIT 1000;
