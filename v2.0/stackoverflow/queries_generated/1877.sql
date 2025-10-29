-- {"query": "1877.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2241} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS TotalUserViews,
        u.UpVotes AS TotalUserUpVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersGiven,
        SUM(p.Score) AS TotalPostScoreByOwner,
        AVG(p.Score) AS AvgPostScoreByOwner,
        MAX(p.CreationDate) AS LastPostDate,
        DATE_PART('day', CURRENT_TIMESTAMP - u.CreationDate) AS AccountAgeDays,
        (SELECT AVG(ans.Score) FROM Posts ans WHERE ans.OwnerUserId = u.Id AND ans.PostTypeId = 2) AS AvgAnswerScoreCorrelated,
        COUNT(DISTINCT b.Id) AS TotalBadgesAwarded,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        MAX(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS HasTagBasedBadge,
        CASE
            WHEN u.Reputation > 10000 AND COUNT(DISTINCT p.Id) > 50 THEN 'High-Rep & Prolific'
            WHEN u.Reputation > 2000 THEN 'Established Contributor'
            ELSE 'Emerging User'
        END AS UserTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.CreationDate
),
QuestionMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionPostDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount AS QuestionCommentCount,
        q.FavoriteCount AS QuestionFavoriteCount,
        q.ClosedDate,
        q.CommunityOwnedDate,
        SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2) AS RawTags,
        TRIM(SPLIT_PART(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><', 1)) AS PrimaryTag,
        LENGTH(q.Body) AS BodyCharacterCount,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(c.Id) AS TotalCommentsOnQuestion,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserRecentQuestionRank,
        NTILE(5) OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS QuestionPopularityQuintile,
        LAG(q.CreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS PrevQuestionDate
    FROM Posts q
    LEFT JOIN Comments c ON q.Id = c.PostId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.FavoriteCount, q.ClosedDate, q.CommunityOwnedDate, q.Tags, q.Body
),
PostHistoryAggregates AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        MAX(ph.CreationDate) AS LastHistoryEvent,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseVoteHistoryCount,
        STRING_AGG(DISTINCT crt.Name, ' | ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS DistinctCloseReasons,
        CASE
            WHEN MAX(ph.PostHistoryTypeId) = 10 THEN TRUE
            ELSE FALSE
        END AS WasEverClosedFlag
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+$' AND ph.Comment::smallint = crt.Id
    GROUP BY ph.PostId
),
RelatedPostActivity AS (
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS OutgoingLinkedCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS OutgoingDuplicateCount
    FROM PostLinks pl
    GROUP BY pl.PostId
    UNION ALL
    SELECT
        pl.RelatedPostId AS PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS IncomingLinkedCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IncomingDuplicateCount
    FROM PostLinks pl
    GROUP BY pl.RelatedPostId
),
CombinedRelatedPostActivity AS (
    SELECT
        PostId,
        COALESCE(SUM(OutgoingLinkedCount), 0) AS TotalOutgoingLinked,
        COALESCE(SUM(OutgoingDuplicateCount), 0) AS TotalOutgoingDuplicate,
        COALESCE(SUM(IncomingLinkedCount), 0) AS TotalIncomingLinked,
        COALESCE(SUM(IncomingDuplicateCount), 0) AS TotalIncomingDuplicate
    FROM RelatedPostActivity
    GROUP BY PostId
)
SELECT
    ues.DisplayName,
    ues.Reputation,
    ues.UserTier,
    qm.QuestionTitle,
    qm.QuestionPostDate,
    qm.QuestionScore,
    qm.ViewCount,
    qm.AnswerCount,
    qm.QuestionFavoriteCount,
    qm.PrimaryTag,
    qm.BodyCharacterCount,
    pha.TotalHistoryEntries AS QuestionHistoryEntries,
    pha.LastEditDate AS QuestionLastEdit,
    pha.EditCount AS QuestionEditCount,
    pha.DistinctCloseReasons,
    cra.TotalOutgoingLinked AS QuestionOutgoingLinks,
    cra.TotalIncomingDuplicate AS QuestionIncomingDuplicates,
    DATE_PART('day', CURRENT_TIMESTAMP - qm.QuestionPostDate) AS DaysSinceQuestion,
    UES.AccountAgeDays,
    NULLIF(qm.QuestionCommentCount, 0) AS NonZeroQuestionCommentCount,
    COALESCE(ues.AvgAnswerScoreCorrelated, 0.0) AS UserAvgAnswerScore,
    qm.QuestionPopularityQuintile,
    (qm.QuestionScore * 2.5 + qm.ViewCount / 100.0 + qm.AnswerCount * 3 + qm.QuestionFavoriteCount * 5) AS WeightedEngagementScore,
    CASE
        WHEN qm.ClosedDate IS NOT NULL AND pha.WasEverClosedFlag THEN 'Closed & Historically Tracked'
        WHEN qm.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer Present'
        WHEN qm.AnswerCount > 0 THEN 'Has Answers'
        ELSE 'No Answers Yet'
    END AS QuestionLifecycleStatus,
    LAG(qm.PrevQuestionDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY ues.UserId ORDER BY qm.QuestionPostDate) AS SecondToLastQuestionDate,
    DENSE_RANK() OVER (ORDER BY ues.Reputation DESC, WeightedEngagementScore DESC) AS GlobalUserQuestionRank,
    SUM(qm.TotalCommentsOnQuestion) OVER (PARTITION BY ues.UserId) AS UserTotalCommentsAcrossQuestions,
    COALESCE(NULLIF(LENGTH(u.AboutMe), 0), 0) AS AboutMeLength,
    u.Location LIKE '%United States%' AS IsUSUser,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = qm.QuestionId AND v.VoteTypeId = 2) AS LastUpVoteDateForQuestion
FROM Users u
RIGHT JOIN UserEngagementSummary ues ON u.Id = ues.UserId
LEFT JOIN QuestionMetrics qm ON u.Id = qm.OwnerUserId
LEFT JOIN PostHistoryAggregates pha ON qm.QuestionId = pha.PostId
FULL OUTER JOIN CombinedRelatedPostActivity cra ON qm.QuestionId = cra.PostId
WHERE
    ues.Reputation > 1000
    AND qm.QuestionScore > 50
    AND qm.ViewCount > 5000
    AND qm.PrimaryTag IS NOT NULL
    AND qm.BodyCharacterCount > 200
    AND (pha.EditCount > 2 OR pha.DistinctCloseReasons IS NOT NULL)
    AND ues.HasTagBasedBadge = 1
    AND qm.QuestionPostDate BETWEEN '2021-01-01' AND '2023-01-01'
    AND (cra.TotalIncomingDuplicate IS NULL OR cra.TotalIncomingDuplicate < 3) -- NULL logic example
    AND u.Location IS NOT NULL
ORDER BY
    WeightedEngagementScore DESC,
    GlobalUserQuestionRank ASC,
    ues.AccountAgeDays DESC,
    qm.QuestionPostDate DESC
LIMIT 5000;
