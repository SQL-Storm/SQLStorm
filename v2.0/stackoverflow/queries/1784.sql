WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(b.Class) FILTER (WHERE b.Id IS NOT NULL) AS AvgBadgeClass,
        MAX(b.Date) AS LastBadgeDate,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.Views
),
PostCommentSummary AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS DirectCommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        p.Title,
        p.Tags,
        p.ParentId,
        LENGTH(p.Body) AS BodyLength,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
            ELSE 'Open'
        END AS PostStatus,
        (SELECT COUNT(DISTINCT C.UserId) FROM Comments C WHERE C.PostId = p.Id AND C.CreationDate >= p.CreationDate) AS TotalCommenters,
        COALESCE(AVG(c.Score), 0) AS AvgCommentScore,
        COALESCE(SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END), 0) AS AnonymousComments,
        (SELECT MAX(C_INNER.CreationDate) FROM Comments C_INNER WHERE C_INNER.PostId = p.Id) AS LatestCommentDate,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostCreationDateByOwner,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS OwnerPostRankByScore,
        -- Replace RANGE BETWEEN INTERVAL with a time-based frame using ROWS between computed rows is not portable.
        -- Use a correlated subquery to compute rolling average per post type over the past 30 days.
        (
            SELECT COALESCE(AVG(p2.Score), 0)
            FROM Posts p2
            WHERE p2.PostTypeId = p.PostTypeId
              AND p2.CreationDate BETWEEN p.CreationDate - INTERVAL '30 days' AND p.CreationDate
        ) AS RollingAvgScoreForPostType
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.CreationDate BETWEEN TIMESTAMP '2020-01-01' AND TIMESTAMP '2023-12-31'
        AND p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastActivityDate, p.ClosedDate, p.Title, p.Tags, p.Body, p.ParentId
),
AggregatedPostHistory AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS TotalEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotesHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosureDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenDate,
        MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (1,2,3)) AS InitialPostDateFromHistory,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS MostRecentEditFromHistory,
        NULLIF(
            SUBSTRING(
                MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Text LIKE '%"OriginalQuestionIds":%' THEN ph.Text END),
                POSITION('"OriginalQuestionIds": [' IN MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Text LIKE '%"OriginalQuestionIds":%' THEN ph.Text END)) + CHAR_LENGTH('"OriginalQuestionIds": ['),
                POSITION(']' IN MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Text LIKE '%"OriginalQuestionIds":%' THEN ph.Text END)) - (POSITION('"OriginalQuestionIds": [' IN MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Text LIKE '%"OriginalQuestionIds":%' THEN ph.Text END)) + CHAR_LENGTH('"OriginalQuestionIds": ['))
            ),
            ''
        ) AS LastDuplicateInfo
    FROM
        PostHistory ph
    GROUP BY
        ph.PostId
),
TagPerformance AS (
    SELECT
        LOWER(TRIM(tag)) AS TagName,
        COUNT(s.PostId) AS PostCountWithTag,
        AVG(s.PostScore) AS AvgScoreForTag,
        SUM(s.ViewCount) AS TotalViewsForTag,
        SUM(s.FavoriteCount) AS TotalFavoritesForTag,
        SUM(s.DirectCommentCount) AS TotalCommentsForTag
    FROM
        PostCommentSummary s,
        UNNEST(string_to_array(SUBSTRING(s.Tags FROM 2 FOR CHAR_LENGTH(s.Tags)-2), '><')) AS tag
    WHERE
        s.Tags IS NOT NULL AND CHAR_LENGTH(s.Tags) > 2
    GROUP BY
        LOWER(TRIM(tag))
    HAVING
        COUNT(s.PostId) > 50 AND AVG(s.PostScore) > 0
),
TopTagsByPerformance AS (
    SELECT
        tp.TagName,
        tp.PostCountWithTag,
        tp.AvgScoreForTag,
        tp.TotalViewsForTag,
        NTILE(5) OVER (ORDER BY tp.AvgScoreForTag DESC) AS ScoreDecile,
        RANK() OVER (ORDER BY tp.TotalViewsForTag DESC) AS ViewRank
    FROM
        TagPerformance tp
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicatePostsCount,
        MAX(pl.CreationDate) AS LastLinkDate,
        SUM(CASE WHEN rt.PostTypeId = 1 THEN 1 ELSE 0 END) AS LinkedQuestionsCount
    FROM
        PostLinks pl
    LEFT JOIN
        Posts rt ON pl.RelatedPostId = rt.Id
    GROUP BY
        pl.PostId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserProfileViews,
    ue.TotalBadges,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.AvgBadgeClass,
    ue.LastBadgeDate,
    pcs.PostId,
    pt.Name AS PostTypeName,
    pcs.PostCreationDate,
    pcs.PostScore,
    pcs.ViewCount,
    pcs.AnswerCount,
    pcs.DirectCommentCount,
    pcs.FavoriteCount,
    pcs.PostStatus,
    pcs.BodyLength,
    pcs.TotalCommenters,
    pcs.AvgCommentScore,
    pcs.AnonymousComments,
    pcs.LatestCommentDate,
    (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - pcs.PostCreationDate)) / (60 * 60 * 24)) AS DaysSincePostCreation,
    (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - pcs.LastActivityDate)) / (60 * 60 * 24)) AS DaysSinceLastPostActivity,
    CASE
        WHEN pcs.PostScore > 50 AND pcs.FavoriteCount > 10 AND pcs.ViewCount > 1000 THEN 'High Engagement'
        WHEN pcs.PostScore > 20 OR pcs.ViewCount > 500 OR pcs.TotalCommenters > 5 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementCategory,
    pcs.OwnerPostRankByScore,
    pcs.RollingAvgScoreForPostType,
    (SELECT AVG(SubP.Score) FROM Posts SubP WHERE SubP.OwnerUserId = ue.UserId AND SubP.Id != pcs.PostId) AS AvgOtherPostsScoreByOwner,
    aph.TotalEdits,
    aph.CloseVotesHistory,
    aph.LastClosureDate,
    aph.LastReopenDate,
    aph.LastDuplicateInfo,
    tt.TagName AS TopPerformingTag,
    tt.AvgScoreForTag AS TopTagAvgScore,
    tt.ViewRank AS TopTagViewRank,
    tt.ScoreDecile AS TopTagScoreDecile,
    pla.LinkedPostsCount,
    pla.DuplicatePostsCount,
    pla.LinkedQuestionsCount,
    (pcs.PostScore * 0.7 + pcs.FavoriteCount * 2.5 + pcs.ViewCount * 0.15 + pcs.TotalCommenters * 3.5 + ue.Reputation * 0.01) AS CustomPostImpactMetric,
    COALESCE(pcs.PrevPostCreationDateByOwner, ue.UserCreationDate) AS EffectivePrevActivityDate,
    CASE WHEN ue.UpVotes = 0 THEN NULL ELSE CAST(NULLIF(ue.DownVotes, 0) AS DECIMAL) / CAST(NULLIF(ue.UpVotes, 0) AS DECIMAL) END AS UserVoteRatio,
    (SELECT
        COUNT(DISTINCT v.UserId)
     FROM
        Votes v
     WHERE
        v.PostId = pcs.PostId
        AND v.VoteTypeId = 2
        AND v.CreationDate BETWEEN pcs.PostCreationDate AND pcs.PostCreationDate + INTERVAL '7 days'
    ) AS UpvotersFirstWeek,
    (SELECT
        AVG(SubC.Score)
     FROM
        Comments SubC
     WHERE
        SubC.UserId = ue.UserId
        AND SubC.PostId != pcs.PostId
    ) AS AvgCommentScoreByUser,
    CASE
        WHEN pcs.Title IS NULL THEN 'No Title'
        WHEN LENGTH(pcs.Title) < 50 THEN 'Short Title'
        WHEN LENGTH(pcs.Title) < 100 THEN 'Medium Title'
        ELSE 'Long Title'
    END AS TitleLengthCategory,
    (CASE WHEN pcs.PostId IS NULL AND ue.UserId IS NULL THEN CAST(TRUE AS BOOLEAN) ELSE CAST(FALSE AS BOOLEAN) END) AS IsOrphanedDataRow
FROM
    UserEngagement ue
INNER JOIN
    PostCommentSummary pcs ON ue.UserId = pcs.OwnerUserId
INNER JOIN
    PostTypes pt ON pcs.PostTypeId = pt.Id
LEFT JOIN
    AggregatedPostHistory aph ON pcs.PostId = aph.PostId
LEFT JOIN LATERAL (
    SELECT TagName, AvgScoreForTag, ViewRank, ScoreDecile
    FROM TopTagsByPerformance
    WHERE TagName IN (
        SELECT LOWER(TRIM(tag))
        FROM UNNEST(string_to_array(SUBSTRING(pcs.Tags FROM 2 FOR CHAR_LENGTH(pcs.Tags)-2), '><')) AS tag
    )
    ORDER BY AvgScoreForTag DESC, ViewRank ASC
    LIMIT 1
) AS tt ON TRUE
LEFT JOIN
    PostLinkAnalysis pla ON pcs.PostId = pla.PostId
WHERE
    ue.Reputation > 5000
    AND pcs.PostScore > 5
    AND pcs.ViewCount > 50
    AND (aph.TotalEdits IS NULL OR aph.TotalEdits < 10)
    AND ue.TotalBadges >= 3
    AND (
        (pcs.PostTypeId = 1 AND pcs.AnswerCount > 0 AND pcs.FavoriteCount > 0) OR
        (pcs.PostTypeId = 2 AND pcs.ParentId IS NOT NULL AND pcs.BodyLength > 100)
    )
    AND COALESCE(pcs.ClosedDate, aph.LastClosureDate) IS NULL
    AND pcs.Title IS NOT NULL
ORDER BY
    CustomPostImpactMetric DESC,
    ue.Reputation DESC,
    DaysSinceLastPostActivity ASC
LIMIT 5000;