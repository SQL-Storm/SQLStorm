-- {"query": "1293.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3129}
WITH UserReputationBuckets AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Views, 0) AS UserViews,
        COALESCE(u.UpVotes, 0) AS UserUpVotes,
        COALESCE(u.DownVotes, 0) AS UserDownVotes,
        CASE
            WHEN u.Reputation >= 100000 THEN 'Legend'
            WHEN u.Reputation >= 25000 THEN 'Expert'
            WHEN u.Reputation >= 5000 THEN 'Advanced'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Novice'
        END AS ReputationTier,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostTimelineEvents AS (
    SELECT
        ph.PostId,
        ph.Id AS HistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS HistoryUserId,
        ph.Comment,
        EXTRACT(EPOCH FROM (LEAD(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) - ph.CreationDate)) AS TimeToNextEventSeconds,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS EventSequence
    FROM PostHistory ph
),
TagPerformanceMetrics AS (
    SELECT
        TagName,
        COUNT(DISTINCT p.Id) AS TotalQuestionsWithTag,
        COALESCE(AVG(p.Score), 0) AS AvgScoreForTag,
        MAX(p.CreationDate) AS LatestQuestionDateForTag,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, AVG(p.Score) DESC, TagName) AS TagPopularityRank
    FROM Posts p,
         LATERAL (SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY TagName
),
DetailedPostAggregates AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        COALESCE(p.Score, 0) AS InitialScore,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.Title,
        p.Tags,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsOnPost,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesOnPost,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesOnPost,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBountyAmount,
        MAX(CASE WHEN pte.PostHistoryTypeId = 10 THEN pte.HistoryDate ELSE NULL END) AS ActualClosedDate,
        MAX(CASE WHEN pte.PostHistoryTypeId = 11 THEN pte.HistoryDate ELSE NULL END) AS ActualReopenedDate,
        COUNT(DISTINCT CASE WHEN pte.PostHistoryTypeId IN (4, 5, 6) THEN pte.HistoryId ELSE NULL END) AS TotalEditCount,
        MIN(pte.HistoryDate) FILTER (WHERE pte.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        AVG(pte.TimeToNextEventSeconds) FILTER (WHERE pte.PostHistoryTypeId IN (4, 5, 6)) AS AvgEditIntervalSeconds
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostTimelineEvents pte ON p.Id = pte.PostId
    GROUP BY p.Id, p.PostTypeId, p.ParentId, p.AcceptedAnswerId, p.OwnerUserId, p.CreationDate, p.Score,
             p.ViewCount, p.AnswerCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.Title, p.Tags
),
QuestionAnalysis AS (
    SELECT
        dpa.PostId,
        dpa.PostTypeId,
        dpa.OwnerUserId,
        dpa.PostCreationDate,
        dpa.Title,
        dpa.InitialScore AS QuestionScore,
        dpa.ViewCount,
        dpa.AnswerCount,
        dpa.FavoriteCount,
        dpa.TotalUpvotesOnPost AS QuestionUpvotes,
        dpa.TotalDownvotesOnPost AS QuestionDownvotes,
        dpa.TotalCommentsOnPost AS QuestionComments,
        dpa.TotalEditCount AS QuestionEditCount,
        dpa.FirstEditDate,
        dpa.AvgEditIntervalSeconds,
        dpa.ClosedDate AS OfficialClosedDate,
        dpa.ActualClosedDate,
        dpa.ActualReopenedDate,
        dpa.CommunityOwnedDate,
        CASE
            WHEN dpa.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            WHEN dpa.ActualReopenedDate IS NOT NULL AND (dpa.ActualClosedDate IS NULL OR dpa.ActualReopenedDate > dpa.ActualClosedDate) THEN 'Reopened'
            WHEN dpa.ClosedDate IS NOT NULL OR dpa.ActualClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS QuestionStatus,
        EXISTS (
            SELECT 1
            FROM Badges b
            WHERE b.UserId = dpa.OwnerUserId
              AND b.Class = 1
              AND b.TagBased = TRUE
              AND dpa.Tags LIKE '%' || b.Name || '%'
        ) AS HasTagBasedGoldBadgeForQuestion,
        CAST(dpa.TotalUpvotesOnPost AS NUMERIC) / NULLIF(dpa.TotalUpvotesOnPost + dpa.TotalDownvotesOnPost + dpa.TotalCommentsOnPost + dpa.ViewCount, 0) AS EngagementRatio,
        dpa.TotalEditCount
    FROM DetailedPostAggregates dpa
    WHERE dpa.PostTypeId = 1
),
AnswerAnalysis AS (
    SELECT
        dpa.PostId,
        dpa.PostTypeId,
        dpa.OwnerUserId,
        dpa.PostCreationDate,
        dpa.ParentId AS QuestionId,
        dpa.InitialScore AS AnswerScore,
        dpa.TotalUpvotesOnPost AS AnswerUpvotes,
        dpa.TotalDownvotesOnPost AS AnswerDownvotes,
        dpa.TotalCommentsOnPost AS AnswerComments,
        dpa.TotalEditCount AS AnswerEditCount,
        dpa.FirstEditDate,
        RANK() OVER (PARTITION BY dpa.ParentId ORDER BY dpa.InitialScore DESC, dpa.PostCreationDate) AS AnswerRankByScore,
        EXISTS (SELECT 1 FROM Posts q WHERE q.Id = dpa.ParentId AND q.AcceptedAnswerId = dpa.PostId) AS IsAcceptedAnswer
    FROM DetailedPostAggregates dpa
    WHERE dpa.PostTypeId = 2
)
SELECT
    ur.UserId,
    ur.DisplayName,
    ur.ReputationTier,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    q.PostId AS QuestionId,
    q.Title AS QuestionTitle,
    q.PostCreationDate AS QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.QuestionStatus,
    q.HasTagBasedGoldBadgeForQuestion,
    q.EngagementRatio,
    ta.TagName AS TopContributingTag,
    ta.TagPopularityRank,
    COALESCE(a.AnswerId, -1) AS TopAnswerId,
    COALESCE(a.AnswerScore, 0) AS TopAnswerScore,
    COALESCE(a.AnswerUpvotes, 0) AS TopAnswerUpvotes,
    COALESCE(a.AnswerDownvotes, 0) AS TopAnswerDownvotes,
    COALESCE(a.IsAcceptedAnswer, FALSE) AS TopAnswerIsAccepted,
    EXTRACT(DAY FROM (q.FirstEditDate - q.PostCreationDate)) AS DaysToFirstQuestionEdit,
    AVG(q.QuestionScore) OVER (PARTITION BY ur.ReputationTier) AS AvgQuestionScoreInTier,
    SUM(q.QuestionUpvotes) OVER (PARTITION BY ur.ReputationTier, EXTRACT(MONTH FROM q.PostCreationDate)) AS MonthlyTierUpvotes,
    q.TotalEditCount
FROM UserReputationBuckets ur
JOIN QuestionAnalysis q ON ur.UserId = q.OwnerUserId
LEFT JOIN (
    SELECT
        aa.PostId AS AnswerId,
        aa.QuestionId,
        aa.AnswerScore,
        aa.AnswerUpvotes,
        aa.AnswerDownvotes,
        aa.IsAcceptedAnswer,
        aa.PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY aa.QuestionId ORDER BY aa.AnswerScore DESC, aa.AnswerUpvotes DESC, aa.PostCreationDate) AS Rn
    FROM AnswerAnalysis aa
) a ON q.PostId = a.QuestionId AND a.Rn = 1
LEFT JOIN (
    SELECT DISTINCT ON (p.Id)
        p.Id AS PostId,
        tpm.TagName,
        tpm.TagPopularityRank
    FROM Posts p,
         LATERAL (SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS PostTagName) t
    JOIN TagPerformanceMetrics tpm ON t.PostTagName = tpm.TagName
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    ORDER BY p.Id, tpm.TagPopularityRank ASC
) ta ON q.PostId = ta.PostId
WHERE q.QuestionScore > 0
  AND q.ViewCount > 100
  AND ur.Reputation >= 1000
  AND q.PostCreationDate >= DATE '2023-01-01'
  AND q.QuestionStatus <> 'CommunityWiki'
  AND q.TotalEditCount > 0

UNION ALL

SELECT
    ur.UserId,
    ur.DisplayName,
    ur.ReputationTier,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    NULL AS QuestionId,
    NULL AS QuestionTitle,
    NULL AS QuestionCreationDate,
    NULL AS QuestionScore,
    NULL AS ViewCount,
    NULL AS AnswerCount,
    NULL AS FavoriteCount,
    'AnswerOnly' AS QuestionStatus,
    FALSE AS HasTagBasedGoldBadgeForQuestion,
    CAST(aa.AnswerUpvotes AS NUMERIC) / NULLIF(aa.AnswerUpvotes + aa.AnswerDownvotes + aa.AnswerComments, 0) AS EngagementRatio,
    NULL AS TopContributingTag,
    NULL AS TagPopularityRank,
    aa.PostId AS TopAnswerId,
    aa.AnswerScore AS TopAnswerScore,
    aa.AnswerUpvotes AS TopAnswerUpvotes,
    aa.AnswerDownvotes AS TopAnswerDownvotes,
    aa.IsAcceptedAnswer AS TopAnswerIsAccepted,
    EXTRACT(DAY FROM (aa.FirstEditDate - aa.PostCreationDate)) AS DaysToFirstQuestionEdit,
    AVG(aa.AnswerScore) OVER (PARTITION BY ur.ReputationTier) AS AvgAnswerScoreInTier,
    SUM(aa.AnswerUpvotes) OVER (PARTITION BY ur.ReputationTier, EXTRACT(MONTH FROM aa.PostCreationDate)) AS MonthlyTierUpvotes,
    aa.AnswerEditCount
FROM UserReputationBuckets ur
JOIN AnswerAnalysis aa ON ur.UserId = aa.OwnerUserId
WHERE ur.ReputationTier IN ('Expert', 'Legend')
  AND aa.AnswerScore > 50
  AND aa.IsAcceptedAnswer = TRUE
  AND aa.PostCreationDate >= DATE '2023-01-01'
  AND aa.AnswerEditCount >= 1
  AND NOT EXISTS (
        SELECT 1
        FROM PostLinks pl
        WHERE pl.PostId = aa.PostId AND pl.LinkTypeId = 3
    );