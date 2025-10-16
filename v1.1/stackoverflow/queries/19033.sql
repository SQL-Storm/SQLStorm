WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) / 86400.0 AS DaysSinceCreation,
        u.Reputation * 1.0 / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) / 86400.0, 0) AS ReputationDensity,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.AcceptedAnswerId,
        p.ClosedDate,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVoteCount,
        (SELECT EXTRACT(EPOCH FROM (MIN(ans.CreationDate) - p.CreationDate)) / 3600.0
         FROM Posts ans
         WHERE ans.Id = p.AcceptedAnswerId AND p.AcceptedAnswerId IS NOT NULL) AS TimeToAcceptedAnswerHours,
        (SELECT AVG(s.Score) FROM Comments s WHERE s.PostId = p.Id AND LOWER(s.Text) LIKE '%' || LOWER('great') || '%' AND s.CreationDate >= p.CreationDate) AS AvgPositiveCommentScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.AcceptedAnswerId, p.ClosedDate, COALESCE(p.FavoriteCount, 0)
),
RecentHighImpactPosts AS (
    SELECT
        phm.PostId,
        phm.OwnerUserId,
        phm.PostTypeId,
        phm.PostCreationDate,
        phm.LastActivityDate,
        phm.Score,
        phm.ViewCount,
        phm.AnswerCount,
        phm.FavoriteCount,
        phm.EditCount,
        phm.CloseVoteCount,
        phm.TimeToAcceptedAnswerHours,
        phm.AvgPositiveCommentScore,
        RANK() OVER (PARTITION BY phm.PostTypeId ORDER BY phm.Score DESC, phm.ViewCount DESC) AS RankByScoreAndViews
    FROM PostHistoricalMetrics phm
    WHERE phm.PostTypeId = 1
      AND phm.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
      AND phm.Score >= 5
      AND phm.ViewCount >= 100
    UNION ALL
    SELECT
        phm.PostId,
        phm.OwnerUserId,
        phm.PostTypeId,
        phm.PostCreationDate,
        phm.LastActivityDate,
        phm.Score,
        phm.ViewCount,
        NULL AS AnswerCount,
        phm.FavoriteCount,
        phm.EditCount,
        phm.CloseVoteCount,
        NULL AS TimeToAcceptedAnswerHours,
        phm.AvgPositiveCommentScore,
        RANK() OVER (PARTITION BY phm.PostTypeId ORDER BY phm.Score DESC, phm.PostCreationDate DESC) AS RankByScoreAndViews
    FROM PostHistoricalMetrics phm
    WHERE phm.PostTypeId = 2
      AND phm.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
      AND phm.Score >= 10
),
TagPerformanceSummary AS (
    SELECT
        tag.unnest_tag AS TagName,
        COUNT(DISTINCT p.Id) AS TaggedQuestionCount,
        AVG(p.Score) AS AvgTagQuestionScore,
        SUM(p.ViewCount) AS TotalTagViewCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS TaggedQuestionsWithAcceptedAnswer,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalTagFavoriteCount
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest_tag
        FROM UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS t(unnest_tag)
    ) tag ON p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    WHERE p.PostTypeId = 1
    GROUP BY tag.unnest_tag
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.DaysSinceCreation,
    uas.ReputationDensity,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalComments,
    uas.TotalBadges,
    COALESCE(uas.AvgQuestionScore, 0) AS AvgQuestionScore,
    COALESCE(uas.AvgAnswerScore, 0) AS AvgAnswerScore,
    rhp.PostId AS HighImpactPostId,
    rhp.PostTypeId AS HighImpactPostType,
    rhp.PostCreationDate AS HighImpactPostDate,
    rhp.Score AS HighImpactPostScore,
    rhp.ViewCount AS HighImpactPostViewCount,
    rhp.AnswerCount AS HighImpactPostAnswerCount,
    rhp.FavoriteCount AS HighImpactPostFavoriteCount,
    rhp.TimeToAcceptedAnswerHours AS HighImpactPostTimeToAcceptedAnswerHours,
    COALESCE(rhp.AvgPositiveCommentScore, 0.0) AS HighImpactPostAvgPositiveCommentScore,
    rhp.RankByScoreAndViews,
    tps.TagName AS TopPerformingTagName,
    tps.AvgTagQuestionScore AS TopPerformingTagAvgScore,
    tps.TotalTagViewCount AS TopPerformingTagTotalViews,
    COALESCE(
        (uas.TotalQuestions * COALESCE(uas.AvgQuestionScore, 0) + uas.TotalAnswers * COALESCE(uas.AvgAnswerScore, 0))
        / NULLIF(uas.TotalQuestions + uas.TotalAnswers, 0),
        0.0
    ) AS WeightedAvgUserPostScore,
    CASE
        WHEN uas.TotalQuestions > 100 AND uas.TotalAnswers > 200 AND uas.TotalBadges > 50 AND uas.Reputation > 50000 THEN 'Legendary Contributor'
        WHEN uas.TotalQuestions > 50 AND uas.TotalAnswers > 100 AND uas.TotalBadges > 20 AND uas.Reputation > 10000 THEN 'High Activity & Influencer'
        WHEN uas.TotalPosts > 10 AND uas.TotalComments > 50 AND uas.DaysSinceCreation > 90 THEN 'Moderate Active User'
        WHEN uas.DaysSinceCreation IS NULL OR uas.DaysSinceCreation < 30 OR uas.TotalPosts = 0 THEN 'New/Inactive User'
        ELSE 'Casual Participant'
    END AS UserActivityLevel,
    CASE
        WHEN rhp.PostId IS NOT NULL AND rhp.EditCount >= 3 AND rhp.CloseVoteCount > 0 THEN 'Active Editor & Moderator Helper'
        WHEN rhp.PostId IS NOT NULL AND rhp.EditCount >= 1 THEN 'Recent High Contributor & Editor'
        WHEN rhp.PostId IS NOT NULL THEN 'Recent High Contributor'
        ELSE 'Standard Contributor'
    END AS UserContributionProfile,
    UPPER(TRIM(SUBSTRING(COALESCE(uas.DisplayName, 'UNKNOWN_USER') FROM 1 FOR 5))) AS DisplayNamePrefix,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = rhp.PostId AND v.VoteTypeId = 2) AS HighImpactPostUpVotes,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = rhp.PostId AND v.VoteTypeId = 3) AS HighImpactPostDownVotes,
    (SELECT SUM(CASE WHEN l.LinkTypeId = 1 THEN 1 ELSE 0 END) FROM PostLinks l WHERE l.RelatedPostId = rhp.PostId) AS LinkedFromOtherPostsCount,
    (SELECT SUM(CASE WHEN l.LinkTypeId = 3 THEN 1 ELSE 0 END) FROM PostLinks l WHERE l.PostId = rhp.PostId) AS DuplicatesOfThisPostCount,
    uas.LastPostActivityDate,
    rhp.TimeToAcceptedAnswerHours,
    rhp.EditCount,
    rhp.CloseVoteCount
FROM UserActivitySummary uas
LEFT JOIN RecentHighImpactPosts rhp ON uas.UserId = rhp.OwnerUserId
LEFT JOIN (
    SELECT
        tps_sub.TagName,
        tps_sub.AvgTagQuestionScore,
        tps_sub.TotalTagViewCount,
        p_user_tag.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p_user_tag.OwnerUserId ORDER BY tps_sub.TotalTagViewCount DESC, tps_sub.AvgTagQuestionScore DESC) AS rn
    FROM Posts p_user_tag
    JOIN LATERAL (
        SELECT tag
        FROM UNNEST(string_to_array(SUBSTRING(p_user_tag.Tags FROM 2 FOR LENGTH(p_user_tag.Tags)-2), '><')) AS t(tag)
    ) tag_name_parsed ON p_user_tag.Tags IS NOT NULL AND LENGTH(p_user_tag.Tags) > 2
    JOIN TagPerformanceSummary tps_sub ON tps_sub.TagName = tag_name_parsed.tag
    WHERE p_user_tag.PostTypeId = 1 AND p_user_tag.OwnerUserId IS NOT NULL
) AS tps ON uas.UserId = tps.OwnerUserId AND tps.rn = 1
WHERE uas.Reputation > 1000
  AND (uas.TotalQuestions > 5 OR uas.TotalAnswers > 10)
  AND (rhp.PostId IS NOT NULL OR uas.LastPostActivityDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'))
  AND (uas.DisplayName ILIKE 'SQL%' OR uas.DisplayName IS NULL)
  AND (rhp.TimeToAcceptedAnswerHours IS NULL OR rhp.TimeToAcceptedAnswerHours <= 72)
ORDER BY uas.Reputation DESC, WeightedAvgUserPostScore DESC, rhp.RankByScoreAndViews ASC
LIMIT 200;