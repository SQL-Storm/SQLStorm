WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE NULL END) AS AvgRelevantPostScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 5 AND u.Reputation > 1000
),
HighImpactQuestions AS (
    SELECT
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastActivityDate,
        LENGTH(p.Body) AS BodyLength, COALESCE(p.Title, '') AS PostTitle, p.Tags, p.ParentId, p.CommunityOwnedDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 5000 AND p.FavoriteCount > 20
      AND p.CreationDate >= TIMESTAMP '2020-01-01' AND p.CommunityOwnedDate IS NULL
),
HighImpactAnswers AS (
    SELECT
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastActivityDate,
        LENGTH(p.Body) AS BodyLength, COALESCE(p.Title, '') AS PostTitle, p.Tags, p.ParentId, p.CommunityOwnedDate
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 50 AND p.ParentId IS NOT NULL
      AND p.CreationDate >= TIMESTAMP '2020-01-01' AND p.CommunityOwnedDate IS NULL
),
PostDetails AS (
    SELECT
        hi.Id AS PostId,
        hi.PostTypeId,
        hi.OwnerUserId,
        hi.CreationDate AS PostCreationDate,
        hi.Score AS PostScore,
        hi.ViewCount,
        hi.AnswerCount,
        hi.CommentCount AS PostCommentCount,
        hi.FavoriteCount,
        hi.LastActivityDate,
        hi.BodyLength,
        hi.PostTitle,
        hi.Tags,
        hi.ParentId,
        (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId = hi.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
        ROW_NUMBER() OVER (PARTITION BY hi.OwnerUserId, hi.PostTypeId ORDER BY hi.Score DESC, hi.CreationDate DESC) AS PostScoreRankByUserType
    FROM HighImpactQuestions hi
    UNION ALL
    SELECT
        hi.Id AS PostId,
        hi.PostTypeId,
        hi.OwnerUserId,
        hi.CreationDate AS PostCreationDate,
        hi.Score AS PostScore,
        hi.ViewCount,
        hi.AnswerCount,
        hi.CommentCount AS PostCommentCount,
        hi.FavoriteCount,
        hi.LastActivityDate,
        hi.BodyLength,
        hi.PostTitle,
        hi.Tags,
        hi.ParentId,
        (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId = hi.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
        ROW_NUMBER() OVER (PARTITION BY hi.OwnerUserId, hi.PostTypeId ORDER BY hi.Score DESC, hi.CreationDate DESC) AS PostScoreRankByUserType
    FROM HighImpactAnswers hi
),
RecentPostActivity AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LatestHistoryDate,
        (SELECT ph_inner.PostHistoryTypeId
         FROM PostHistory ph_inner
         WHERE ph_inner.PostId = ph.PostId
           AND ph_inner.CreationDate = MAX(ph.CreationDate)
         LIMIT 1
        ) AS LatestPostHistoryType,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) AS CloseReopenEvents
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY ph.PostId
),
UserBadgeDiversity AS (
    SELECT
        b.UserId,
        COUNT(DISTINCT b.Class) AS DistinctBadgeClasses,
        COUNT(DISTINCT b.Name) AS DistinctBadgeNames,
        COUNT(DISTINCT CASE WHEN b.TagBased = TRUE THEN b.Name ELSE NULL END) AS DistinctTagBadges
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(DISTINCT b.Class) >= 3
),
QuestionTagAnalysis AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        LOWER(TRIM(tag)) AS TagName,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId, LOWER(TRIM(tag))) AS UserTagScoreSum,
        COUNT(p.Id) OVER (PARTITION BY p.OwnerUserId, LOWER(TRIM(tag))) AS UserTagPostCount
    FROM Posts p,
    LATERAL (
      SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag
    ) AS tags
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
LinkedPostsInfo AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN plt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks,
        AVG(COALESCE(p_related.Score, 0)) AS AvgRelatedPostScore
    FROM PostLinks pl
    JOIN LinkTypes plt ON pl.LinkTypeId = plt.Id
    LEFT JOIN Posts p_related ON pl.RelatedPostId = p_related.Id
    GROUP BY pl.PostId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalCommentsMade,
    ue.TotalBadges,
    ubd.DistinctBadgeClasses,
    ubd.DistinctTagBadges,
    pd.PostId,
    pd.PostTitle,
    pd.PostScore,
    pd.ViewCount,
    pd.PostScoreRankByUserType,
    pd.BodyLength,
    rpa.LatestHistoryDate,
    rpa.LatestPostHistoryType,
    rpa.CloseReopenEvents,
    lpi.TotalLinkedPosts,
    lpi.DuplicateLinks,
    lpi.AvgRelatedPostScore,
    qa.TagName,
    qa.UserTagScoreSum,
    qa.UserTagPostCount,
    (SELECT COUNT(DISTINCT c_sub.Id)
     FROM Comments c_sub
     WHERE c_sub.PostId = pd.PostId
       AND c_sub.CreationDate > pd.LastActivityDate
       AND c_sub.UserId IS NOT NULL
    ) AS NewCommentsAfterLastActivity,
    CASE
        WHEN ue.AvgRelevantPostScore > 50 AND pd.PostScore > 100 THEN 'HighImpactPost'
        WHEN ue.AvgRelevantPostScore > 20 AND pd.ViewCount > 5000 THEN 'PopularPostByEngagedUser'
        WHEN pd.BodyLength > 1000 AND pd.PostCommentCount > 20 THEN 'DetailedDiscussedPost'
        ELSE 'StandardPost'
    END AS PostImpactCategory,
    (ue.Reputation * 0.1 + ue.TotalPosts * 0.5 + ue.TotalCommentsMade * 0.2 + COALESCE(ubd.DistinctBadgeClasses, 0) * 5 + COALESCE(ubd.DistinctTagBadges, 0) * 10) AS UserEngagementScoreWeighted,
    AVG(pd.PostScore) OVER (PARTITION BY qa.TagName) AS AvgPostScoreForTag,
    RANK() OVER (PARTITION BY qa.TagName ORDER BY qa.UserTagScoreSum DESC) AS UserRankInTagByScore,
    COALESCE(SUBSTRING(pd.Tags FROM POSITION('<' IN pd.Tags) + 1 FOR POSITION('>' IN pd.Tags) - POSITION('<' IN pd.Tags) - 1), 'no_primary_tag') AS PrimaryTag,
    CASE WHEN pd.FavoriteCount IS NULL OR pd.FavoriteCount = 0 THEN FALSE ELSE TRUE END AS HasFavorites,
    ABS(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - pd.LastActivityDate))) / 3600.0 AS HoursSinceLastPostActivity,
    (SELECT AVG(s.Score) FROM Posts s WHERE s.OwnerUserId = ue.UserId AND s.PostTypeId = 2 AND s.ParentId = pd.PostId) AS AvgAnswerScoreForQuestion
FROM UserEngagement ue
INNER JOIN PostDetails pd ON ue.UserId = pd.OwnerUserId
LEFT JOIN RecentPostActivity rpa ON pd.PostId = rpa.PostId
LEFT JOIN UserBadgeDiversity ubd ON ue.UserId = ubd.UserId
LEFT JOIN LinkedPostsInfo lpi ON pd.PostId = lpi.PostId
LEFT JOIN QuestionTagAnalysis qa ON pd.PostId = qa.QuestionId AND pd.PostTypeId = 1
WHERE
    ue.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
    AND pd.PostScoreRankByUserType <= 5
    AND (rpa.LatestPostHistoryType IS NULL OR rpa.LatestPostHistoryType NOT IN (12, 14))
    AND (qa.TagName LIKE '%sql%' OR qa.TagName LIKE '%database%' OR qa.TagName LIKE '%performance%')
    AND NOT EXISTS (
        SELECT 1
        FROM Comments c_check
        WHERE c_check.PostId = pd.PostId
          AND c_check.Text ILIKE '%spam%'
          AND c_check.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 month')
    )
GROUP BY
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalCommentsMade,
    ue.TotalBadges,
    ubd.DistinctBadgeClasses,
    ubd.DistinctTagBadges,
    pd.PostId,
    pd.PostTitle,
    pd.PostScore,
    pd.ViewCount,
    pd.PostScoreRankByUserType,
    pd.BodyLength,
    rpa.LatestHistoryDate,
    rpa.LatestPostHistoryType,
    rpa.CloseReopenEvents,
    lpi.TotalLinkedPosts,
    lpi.DuplicateLinks,
    lpi.AvgRelatedPostScore,
    qa.TagName,
    qa.UserTagScoreSum,
    qa.UserTagPostCount,
    pd.Tags,
    pd.PostCommentCount,
    pd.LastActivityDate,
    pd.FavoriteCount,
    ue.AvgRelevantPostScore,
    ue.TotalPosts,
    ue.TotalCommentsMade,
    ubd.DistinctBadgeClasses,
    ubd.DistinctTagBadges
ORDER BY
    UserEngagementScoreWeighted DESC,
    AvgPostScoreForTag DESC,
    HoursSinceLastPostActivity ASC
LIMIT 1000;