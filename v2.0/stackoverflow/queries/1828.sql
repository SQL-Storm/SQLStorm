-- {"query": "1828.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3248}
WITH BaseQuestionData AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.LastActivityDate,
        p.ViewCount,
        p.Score AS QuestionScore,
        p.AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.Title,
        p.Tags,
        EXTRACT(DAY FROM (p.LastActivityDate - p.CreationDate)) AS DaysActiveSinceCreation,
        (p.ViewCount * 0.05) + (p.Score * 1.0) + (COALESCE(p.AnswerCount, 0) * 1.5) + (COALESCE(p.FavoriteCount, 0) * 2.5) AS TotalEngagementScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL AND p.CommunityOwnedDate IS NOT NULL THEN 'ClosedAndCommunityOwned'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2019-01-01'
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) AS DistinctHistoryContributors,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS MajorModerationActions,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (11, 13, 15, 20) THEN 1 ELSE 0 END) AS ReversalModerationActions
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId BETWEEN 1 AND 20
    GROUP BY ph.PostId
),
CommentActivity AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentsCount
    FROM Comments c
    GROUP BY c.PostId
),
VoteBreakdown AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS UserFavoriteVotes,
        SUM(CASE WHEN v.VoteTypeId IN (6, 7, 10, 11, 12) THEN 1 ELSE 0 END) AS ModeratorControlVotes,
        COUNT(DISTINCT v.UserId) AS DistinctVoters
    FROM Votes v
    WHERE v.PostId IN (SELECT PostId FROM BaseQuestionData)
    GROUP BY v.PostId
),
DuplicateLinkAggregates AS (
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS NumberOfDuplicatesIdentified,
        STRING_AGG(CAST(pl.RelatedPostId AS VARCHAR), ';') AS DuplicatedToPostIds,
        MAX(CASE WHEN p_related.PostTypeId = 1 THEN 1 ELSE 0 END) AS LinksToAnotherQuestionType
    FROM PostLinks pl
    JOIN Posts p_related ON pl.RelatedPostId = p_related.Id
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
OwnerBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionTagMetrics AS (
    SELECT
        bq.PostId,
        bq.Tags,
        SUM(t.Count) AS CombinedTagPopularityScore,
        COUNT(DISTINCT t.TagName) AS UniqueTagCount,
        MAX(CASE WHEN t.IsModeratorOnly THEN 1 ELSE 0 END) AS HasModeratorOnlyTag,
        AVG(LENGTH(t.TagName)) AS AverageTagNameLength
    FROM BaseQuestionData bq
    CROSS JOIN LATERAL (
        SELECT q_tag
        FROM (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(bq.Tags FROM 2 FOR LENGTH(bq.Tags)-2), '><')) AS q_tag
        ) sub
    ) tags_unnested
    JOIN Tags t ON tags_unnested.q_tag = t.TagName
    GROUP BY bq.PostId, bq.Tags
),
QuestionAnswerPerformance AS (
    SELECT
        p.ParentId AS QuestionId,
        AVG(p.Score) AS AverageAnswerScore,
        MAX(p.CreationDate) AS LatestAnswerDate,
        COUNT(p.Id) AS ActualAnswerCount,
        AVG(EXTRACT(EPOCH FROM (p.CreationDate - q.QuestionCreationDate)) / 3600.0) AS AvgAnswerResponseTimeHours
    FROM Posts p
    JOIN BaseQuestionData q ON p.ParentId = q.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId, q.QuestionCreationDate
)
SELECT
    bq.PostId,
    bq.Title,
    bq.PostStatus,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate,
    bq.QuestionCreationDate,
    bq.LastActivityDate,
    bq.ViewCount,
    bq.QuestionScore,
    COALESCE(qap.ActualAnswerCount, bq.AnswerCount) AS FinalAnswerCount,
    bq.FavoriteCount,
    bq.DaysActiveSinceCreation,
    bq.TotalEngagementScore,
    COALESCE(phd.TotalHistoryEvents, 0) AS TotalHistoryEvents,
    COALESCE(phd.ContentEditCount, 0) AS ContentEditCount,
    COALESCE(phd.MajorModerationActions, 0) AS MajorModerationActions,
    COALESCE(phd.ReversalModerationActions, 0) AS ReversalModerationActions,
    phd.LastHistoryEventDate,
    (COALESCE(phd.ContentEditCount, 0) * 100.0 / NULLIF(COALESCE(phd.TotalHistoryEvents, 0), 0)) AS ContentEditRatio,
    COALESCE(ca.TotalComments, 0) AS TotalComments,
    COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(ca.AvgCommentScore, 0.0) AS AvgCommentScore,
    ca.LastCommentDate,
    COALESCE(ca.AnonymousCommentsCount, 0) AS AnonymousCommentsCount,
    COALESCE(vb.UpVotesReceived, 0) AS UpVotesReceived,
    COALESCE(vb.DownVotesReceived, 0) AS DownVotesReceived,
    COALESCE(vb.UserFavoriteVotes, 0) AS ExplicitUserFavoriteVotes,
    COALESCE(vb.ModeratorControlVotes, 0) AS ModeratorControlVotes,
    (COALESCE(vb.UpVotesReceived, 0) - COALESCE(vb.DownVotesReceived, 0)) AS NetVotes,
    COALESCE(dla.NumberOfDuplicatesIdentified, 0) AS NumberOfDuplicatesIdentified,
    dla.DuplicatedToPostIds,
    CASE WHEN dla.LinksToAnotherQuestionType = 1 THEN TRUE ELSE FALSE END AS LinkedToQuestion,
    COALESCE(obs.TotalBadges, 0) AS OwnerTotalBadges,
    COALESCE(obs.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(obs.TagBasedBadges, 0) AS OwnerTagBasedBadges,
    COALESCE(qtm.CombinedTagPopularityScore, 0) AS QuestionTagsCombinedPopularity,
    COALESCE(qtm.UniqueTagCount, 0) AS UniqueTagCount,
    COALESCE(qtm.HasModeratorOnlyTag, 0) AS HasModeratorOnlyTag,
    COALESCE(qtm.AverageTagNameLength, 0.0) AS AverageTagLength,
    COALESCE(qap.AverageAnswerScore, 0.0) AS AverageAnswerScore,
    COALESCE(qap.LatestAnswerDate, bq.QuestionCreationDate) AS LatestAnswerDate,
    COALESCE(qap.AvgAnswerResponseTimeHours, 0.0) AS AvgAnswerResponseTimeHours,
    ROW_NUMBER() OVER (PARTITION BY bq.PostStatus ORDER BY bq.TotalEngagementScore DESC, bq.ViewCount DESC) AS RankWithinStatus,
    NTILE(10) OVER (ORDER BY bq.TotalEngagementScore DESC) AS EngagementDecile,
    LAG(bq.TotalEngagementScore, 1, 0.0) OVER (ORDER BY bq.QuestionCreationDate, bq.PostId) AS PreviousQuestionEngagementScore,
    AVG(bq.QuestionScore) OVER (PARTITION BY u.AccountId) AS AvgOwnerQuestionScore,
    EXISTS (
        SELECT 1
        FROM PostHistory ph_corr
        WHERE ph_corr.PostId = bq.PostId
          AND ph_corr.PostHistoryTypeId = 10
          AND ph_corr.Comment LIKE '%off-topic%'
          AND ph_corr.CreationDate BETWEEN bq.QuestionCreationDate AND bq.LastActivityDate
    ) AS WasClosedOffTopic,
    UPPER(SUBSTRING(bq.Title FROM 1 FOR 15)) AS TitlePrefixUpper,
    LENGTH(bq.Title) AS TitleLength,
    COALESCE(NULLIF(TRIM(BOTH '<>' FROM SUBSTRING(bq.Tags FROM 2 FOR NULLIF(POSITION('>' IN bq.Tags) - 2, 0))), ''), 'N/A') AS FirstTagStripped,
    CASE
        WHEN bq.Tags IS NULL OR bq.Tags = '<>' THEN 'NoTagsProvided'
        WHEN bq.Tags LIKE '%<sql>%' OR bq.Tags LIKE '%<database>%' THEN 'SQL_Database_Related'
        WHEN bq.Tags LIKE '%<python>%' OR bq.Tags LIKE '%<java>%' THEN 'ProgrammingLanguageSpecific'
        ELSE 'OtherTechnologyTags'
    END AS TagCategoryGroup,
    (bq.TotalEngagementScore / NULLIF(bq.ViewCount, 0.0)) AS EngagementPerViewRatio,
    (u.Reputation * 1.0 / NULLIF(EXTRACT(DAY FROM (bq.QuestionCreationDate - u.CreationDate)), 0)) AS OwnerReputationPerDayAtQuestionDate
FROM BaseQuestionData bq
LEFT JOIN Users u ON bq.OwnerUserId = u.Id
LEFT JOIN PostHistoryDetails phd ON bq.PostId = phd.PostId
LEFT JOIN CommentActivity ca ON bq.PostId = ca.PostId
LEFT JOIN VoteBreakdown vb ON bq.PostId = vb.PostId
LEFT JOIN DuplicateLinkAggregates dla ON bq.PostId = dla.PostId
LEFT JOIN OwnerBadgeSummary obs ON bq.OwnerUserId = obs.UserId
LEFT JOIN QuestionTagMetrics qtm ON bq.PostId = qtm.PostId
LEFT JOIN QuestionAnswerPerformance qap ON bq.PostId = qap.QuestionId
WHERE bq.TotalEngagementScore > 50
  AND bq.ViewCount > 100
  AND (bq.AnswerCount IS NULL OR bq.AnswerCount > 0)
ORDER BY bq.TotalEngagementScore DESC, bq.QuestionCreationDate DESC, bq.PostId
LIMIT 7500;