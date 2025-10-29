WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostContributions AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
FeaturedTags AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS TaggedQuestionCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    WHERE COALESCE(CAST(t.IsRequired AS INTEGER), 0) = 0
      AND COALESCE(CAST(t.IsModeratorOnly AS INTEGER), 0) = 0
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 1000
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.FavoriteCount DESC) AS RankByScoreAndFavorites
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserReputationRank AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        NTILE(10) OVER (ORDER BY u.Reputation DESC) AS ReputationBucket
    FROM Users u
),
TagWikiPopularity AS (
    SELECT
        t.TagName,
        COALESCE(tp.Count, 0) AS TagCount,
        COALESCE(p.ViewCount, 0) AS WikiViewCount,
        COALESCE(p.CommentCount, 0) AS WikiCommentCount
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
    LEFT JOIN Tags tp ON t.TagName = tp.TagName
    WHERE t.WikiPostId IS NOT NULL
)
SELECT
    pe.PostId,
    pe.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    pe.CreationDate AS PostCreationDate,
    pe.Score AS PostScore,
    pe.AnswerCount AS PostAnswerCount,
    pe.CommentCount AS PostCommentCount,
    pe.FavoriteCount AS PostFavoriteCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.IsClosed,
    pe.RankByScoreAndFavorites,
    pc.QuestionCount,
    pc.AnswerCount AS UserAnswerCount,
    pc.PositiveScorePosts,
    uca.CommentCount AS UserCommentCount,
    uca.PositiveScoreComments,
    uca.AvgCommentScore,
    urr.ReputationBucket,
    MAX(CASE WHEN rpe.rn = 1 THEN rpe.EditDate ELSE NULL END) AS LastEditDate,
    twp.TagCount,
    twp.WikiViewCount,
    twp.WikiCommentCount,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = pe.PostId AND pl.LinkTypeId = 3) THEN 'IsDuplicate'
        WHEN pe.Score > 1000 AND pe.AnswerCount > 50 THEN 'Highly Engaged'
        WHEN pe.FavoriteCount > 10 THEN 'Favorited'
        ELSE 'Standard'
    END AS EngagementCategory,
    (u.DisplayName || ' (' || COALESCE(CAST(urr.Reputation AS VARCHAR), CAST(u.Reputation AS VARCHAR)) || ')') AS UserIdentifier
FROM PostEngagement pe
LEFT JOIN Users u ON pe.OwnerUserId = u.Id
LEFT JOIN UserPostContributions pc ON pe.OwnerUserId = pc.UserId
LEFT JOIN UserCommentActivity uca ON pe.OwnerUserId = uca.UserId
LEFT JOIN RankedPostEdits rpe ON pe.PostId = rpe.PostId
LEFT JOIN UserReputationRank urr ON pe.OwnerUserId = urr.UserId
LEFT JOIN TagWikiPopularity twp ON EXISTS (
    SELECT 1 FROM Posts p_tags WHERE p_tags.Id = pe.PostId AND p_tags.Tags LIKE '%' || twp.TagName || '%'
)
WHERE u.Id IS NOT NULL
    AND uca.UserId IS NOT NULL
    AND pe.Score > 0
    AND pe.CreationDate > DATE '2023-01-01'
GROUP BY
    pe.PostId,
    pe.OwnerUserId,
    u.DisplayName,
    pe.CreationDate,
    pe.Score,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.IsClosed,
    pe.RankByScoreAndFavorites,
    pc.QuestionCount,
    pc.AnswerCount,
    pc.PositiveScorePosts,
    uca.CommentCount,
    uca.PositiveScoreComments,
    uca.AvgCommentScore,
    urr.ReputationBucket,
    twp.TagCount,
    twp.WikiViewCount,
    twp.WikiCommentCount,
    u.Reputation,
    uca.UserId,
    rpe.rn,
    rpe.EditDate,
    urr.Reputation
HAVING MAX(CASE WHEN rpe.rn = 1 THEN rpe.EditDate ELSE NULL END) IS NOT NULL

UNION

SELECT
    NULL AS PostId,
    NULL AS OwnerUserId,
    NULL AS OwnerDisplayName,
    NULL AS PostCreationDate,
    NULL AS PostScore,
    NULL AS PostAnswerCount,
    NULL AS PostCommentCount,
    NULL AS PostFavoriteCount,
    NULL AS UpVoteCount,
    NULL AS DownVoteCount,
    NULL AS IsClosed,
    NULL AS RankByScoreAndFavorites,
    NULL AS QuestionCount,
    NULL AS UserAnswerCount,
    NULL AS PositiveScorePosts,
    NULL AS UserCommentCount,
    NULL AS PositiveScoreComments,
    NULL AS AvgCommentScore,
    NULL AS ReputationBucket,
    NULL AS LastEditDate,
    twp.TagCount,
    twp.WikiViewCount,
    twp.WikiCommentCount,
    'FeaturedTag' AS EngagementCategory,
    NULL AS UserIdentifier
FROM FeaturedTags ft
LEFT JOIN TagWikiPopularity twp ON ft.TagName = twp.TagName
WHERE twp.WikiViewCount > 5000
ORDER BY PostScore DESC NULLS LAST, TagCount DESC;