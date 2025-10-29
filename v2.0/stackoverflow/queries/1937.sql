-- {"query": "1937.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3826}
WITH UserActivityCTE AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COALESCE(SUM(p.AnswerCount), 0) AS TotalAnswersReceivedForQuestions,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoriteCountOnPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
CommentActivityCTE AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentActivityDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
BadgeSummaryCTE AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostLinkMetricsCTE AS (
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        COUNT(pl.RelatedPostId) AS TotalRelatedLinks
    FROM PostLinks pl
    GROUP BY pl.PostId
),
PostHistoryEventsCTE AS (
    SELECT
        ph.Id,
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        CASE
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) AND ph.Text IS NOT NULL AND ph.Text LIKE '{%}'
            THEN json_array_length(cast(ph.Text AS json) -> 'Voters')
            ELSE 0
        END AS JsonVoterCount,
        CASE
            WHEN ph.PostHistoryTypeId = 10 AND ph.Text IS NOT NULL AND ph.Text LIKE '{%}'
            THEN json_array_length(cast(ph.Text AS json) -> 'OriginalQuestionIds')
            ELSE 0
        END AS JsonDuplicateTargetCount
    FROM PostHistory ph
),
UserModerationActivityCTE AS (
    SELECT
        phe.UserId,
        SUM(CASE WHEN phe.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS UserCloseVotes,
        SUM(CASE WHEN phe.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS UserReopenVotes,
        SUM(CASE WHEN phe.PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS UserDeleteUndeleteVotes,
        SUM(CASE WHEN phe.PostHistoryTypeId IN (14, 15) THEN 1 ELSE 0 END) AS UserLockUnlockActions,
        COUNT(DISTINCT phe.PostId) AS DistinctModeratedPosts,
        SUM(COALESCE(phe.JsonVoterCount, 0)) AS TotalJsonVotersOnActions,
        SUM(COALESCE(phe.JsonDuplicateTargetCount, 0)) AS TotalJsonDuplicateTargets
    FROM PostHistoryEventsCTE phe
    WHERE phe.UserId IS NOT NULL
      AND phe.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
    GROUP BY phe.UserId
),
QuestionTagStatsCTE AS (
    SELECT
        p.Id AS PostId,
        REPLACE(REPLACE(SUBSTRING(TRIM(BOTH '>' FROM UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))), 1), '&lt;', '<'), '&gt;', '>') AS TagNameClean,
        p.Score,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
AggregatedTagMetricsCTE AS (
    SELECT
        TagNameClean,
        COUNT(DISTINCT PostId) AS TaggedQuestionsCount,
        AVG(Score) AS AvgQuestionScoreForTag,
        AVG(ViewCount) AS AvgQuestionViewCountForTag
    FROM QuestionTagStatsCTE
    GROUP BY TagNameClean
),
UserLatestQuestionCTE AS (
    SELECT
        p.OwnerUserId,
        p.Id AS LatestQuestionId,
        p.Title AS LatestQuestionTitle,
        p.Score AS LatestQuestionScore,
        p.CreationDate AS LatestQuestionCreationDate,
        plm.LinkedPostsCount,
        plm.DuplicatePostsCount,
        p.Tags AS LatestQuestionTagsRaw,
        (SELECT
             REPLACE(REPLACE(SUBSTRING(t.Tag, 2, LENGTH(t.Tag) - 2), '&lt;', '<'), '&gt;', '>')
         FROM LATERAL UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS t(Tag)
         LIMIT 1
        ) AS LatestQuestionPrimaryTag,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN PostLinkMetricsCTE plm ON p.Id = plm.PostId
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
UserInfluenceSummaryCTE AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ua.TotalPosts, 0) AS TotalPosts,
        COALESCE(ua.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(ua.TotalPostViews, 0) AS TotalPostViews,
        COALESCE(ua.QuestionsAsked, 0) AS QuestionsAsked,
        COALESCE(ua.AnswersGiven, 0) AS AnswersGiven,
        COALESCE(ua.TotalAnswersReceivedForQuestions, 0) AS AnswersReceived,
        COALESCE(ca.TotalComments, 0) AS TotalComments,
        COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(bs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ma.UserCloseVotes, 0) AS CloseVotesCast,
        COALESCE(ma.UserReopenVotes, 0) AS ReopenVotesCast,
        COALESCE(ma.DistinctModeratedPosts, 0) AS DistinctModeratedPosts,
        (u.UpVotes - u.DownVotes) AS NetUserVotes,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) / (60 * 60 * 24 * 365.25) AS YearsOnPlatform,
        (u.UpVotes + u.DownVotes) AS TotalVoteEngagement,
        NULLIF(u.Views, 0) AS ProfileViews,
        COALESCE(ma.TotalJsonVotersOnActions, 0) AS TotalModerationJsonVoters,
        COALESCE(ma.TotalJsonDuplicateTargets, 0) AS TotalModerationJsonDuplicateTargets
    FROM Users u
    LEFT JOIN UserActivityCTE ua ON u.Id = ua.UserId
    LEFT JOIN CommentActivityCTE ca ON u.Id = ca.UserId
    LEFT JOIN BadgeSummaryCTE bs ON u.Id = bs.UserId
    LEFT JOIN UserModerationActivityCTE ma ON u.Id = ma.UserId
)
SELECT
    uis.UserId,
    uis.DisplayName,
    uis.Reputation,
    uis.GoldBadges,
    uis.SilverBadges,
    uis.BronzeBadges,
    uis.TotalPosts,
    uis.QuestionsAsked,
    uis.AnswersGiven,
    uis.TotalPostScore,
    uis.TotalPostViews,
    uis.TotalComments,
    uis.NetUserVotes,
    uis.YearsOnPlatform,
    uis.CloseVotesCast,
    uis.ReopenVotesCast,
    uis.DistinctModeratedPosts,
    uis.TotalModerationJsonVoters,
    uis.TotalModerationJsonDuplicateTargets,
    (SELECT COUNT(DISTINCT p_q.Id)
     FROM Posts p_q
     JOIN Posts p_ans ON p_q.Id = p_ans.ParentId
     WHERE p_q.OwnerUserId = uis.UserId
       AND p_ans.OwnerUserId = uis.UserId
       AND p_q.PostTypeId = 1 AND p_ans.PostTypeId = 2
    ) AS SelfAnsweredQuestionsCount,
    (SELECT MAX(c.Score)
     FROM Comments c
     JOIN Posts p ON c.PostId = p.Id
     WHERE p.OwnerUserId = uis.UserId AND c.UserId IS NOT NULL
    ) AS MaxCommentScoreOnOwnPost,
    RANK() OVER (ORDER BY uis.TotalPostScore DESC, uis.Reputation DESC) AS OverallPostScoreRank,
    AVG(uis.Reputation) OVER (PARTITION BY FLOOR(uis.Reputation / 1000) * 1000) AS AvgReputationInBracket,
    CAST(
        (uis.Reputation * 0.4) +
        (uis.TotalPostScore * 0.3) +
        (uis.GoldBadges * 10.0) +
        (uis.SilverBadges * 5.0) +
        (uis.TotalPosts * 0.1) +
        (uis.AnswersGiven * 0.2) +
        (COALESCE(uis.ProfileViews, 1) * 0.001) +
        (uis.CloseVotesCast * 2.0) +
        (uis.ReopenVotesCast * 3.0)
    AS NUMERIC(18, 2)) AS InfluenceScore,
    COALESCE(
        CASE
            WHEN u.Location ILIKE '%United States%' OR u.Location ILIKE '%USA%' THEN 'USA'
            WHEN u.Location ILIKE '%Canada%' THEN 'Canada'
            WHEN u.Location ILIKE '%UK%' OR u.Location ILIKE '%United Kingdom%' THEN 'UK'
            WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN 'Unknown'
            ELSE 'Other_Location'
        END, 'Unknown'
    ) AS UserRegion,
    lq.LatestQuestionTitle,
    lq.LatestQuestionScore,
    lq.LatestQuestionCreationDate,
    COALESCE(lq.LinkedPostsCount, 0) AS LatestQuestionLinkedPosts,
    COALESCE(lq.DuplicatePostsCount, 0) AS LatestQuestionDuplicatePosts,
    COALESCE(lq.LatestQuestionPrimaryTag, 'No_Primary_Tag') AS LatestQuestionPrimaryTag,
    COALESCE(atm.AvgQuestionScoreForTag, 0.0) AS AvgScoreForLatestQuestionPrimaryTag,
    COALESCE(atm.AvgQuestionViewCountForTag, 0.0) AS AvgViewCountForLatestQuestionPrimaryTag,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostHistoryEventsCTE phe_check
            JOIN Posts p_check ON phe_check.PostId = p_check.Id
            WHERE phe_check.UserId = uis.UserId
              AND phe_check.PostHistoryTypeId = 10
              AND p_check.PostTypeId = 1
              AND p_check.ViewCount > 50000
              AND p_check.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
        ) THEN TRUE
        ELSE FALSE
    END AS ClosedRecentHighViewQuestion,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Badges b_tag
            JOIN QuestionTagStatsCTE qts ON b_tag.Name = qts.TagNameClean
            JOIN AggregatedTagMetricsCTE atm_tag ON qts.TagNameClean = atm_tag.TagNameClean
            WHERE b_tag.UserId = uis.UserId
              AND b_tag.Class = 1
              AND atm_tag.AvgQuestionScoreForTag > 50
        ) THEN TRUE
        ELSE FALSE
    END AS HasGoldBadgeForHighScoreTag
FROM Users u
JOIN UserInfluenceSummaryCTE uis ON u.Id = uis.UserId
LEFT JOIN UserLatestQuestionCTE lq ON uis.UserId = lq.OwnerUserId AND lq.rn = 1
LEFT JOIN AggregatedTagMetricsCTE atm ON lq.LatestQuestionPrimaryTag = atm.TagNameClean
WHERE uis.Reputation >= 1000
  AND (uis.QuestionsAsked > 5 OR uis.AnswersGiven > 10)
  AND (uis.GoldBadges > 0 OR uis.SilverBadges > 2)
  AND uis.YearsOnPlatform >= 1.0
  AND (
      (uis.Reputation * 0.4) +
      (uis.TotalPostScore * 0.3) +
      (uis.GoldBadges * 10.0) +
      (uis.SilverBadges * 5.0) +
      (uis.TotalPosts * 0.1) +
      (uis.AnswersGiven * 0.2) +
      (COALESCE(uis.ProfileViews, 1) * 0.001) +
      (uis.CloseVotesCast * 2.0) +
      (uis.ReopenVotesCast * 3.0)
  ) > 500.00
  AND uis.TotalVoteEngagement > 100
  AND (uis.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'))
ORDER BY
    CAST(
        (uis.Reputation * 0.4) +
        (uis.TotalPostScore * 0.3) +
        (uis.GoldBadges * 10.0) +
        (uis.SilverBadges * 5.0) +
        (uis.TotalPosts * 0.1) +
        (uis.AnswersGiven * 0.2) +
        (COALESCE(uis.ProfileViews, 1) * 0.001) +
        (uis.CloseVotesCast * 2.0) +
        (uis.ReopenVotesCast * 3.0)
    AS NUMERIC(18,2)) DESC,
    OverallPostScoreRank ASC,
    uis.Reputation DESC
LIMIT 100;