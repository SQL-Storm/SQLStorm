WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN rp.PostTypeId = 1 AND rp.PostScore > 50 THEN 1 ELSE 0 END) AS HighScoreQuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 AND rp.PostScore > 10 THEN 1 ELSE 0 END) AS HighScoreAnswerCount,
        AVG(CASE WHEN rp.PostTypeId = 1 THEN rp.PostScore END) AS AvgQuestionScore,
        AVG(CASE WHEN rp.PostTypeId = 2 THEN rp.PostScore END) AS AvgAnswerScore,
        SUM(rp.PostViewCount) AS TotalViews,
        SUM(rp.FavoriteCount) AS TotalFavorites,
        SUM(rp.CommentCount) AS TotalComments,
        COUNT(CASE WHEN rp.ClosedDate IS NOT NULL THEN rp.PostId ELSE NULL END) AS ClosedPostCount,
        MAX(rp.PostCreationDate) AS LatestPostDate,
        SUM(CASE WHEN rp.rn <= 10 THEN 1 ELSE 0 END) AS RecentPostsCount
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfLinks,
        MAX(pl.CreationDate) AS LatestLinkDate,
        (
         SELECT STRING_AGG(lt2.Name, ', ' ORDER BY lt2.Name)
         FROM LinkTypes lt2
         JOIN PostLinks pl2 ON pl2.LinkTypeId = lt2.Id
         WHERE pl2.PostId = pl.PostId
        ) AS LinkTypesUsed
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS NumberOfComments,
        MAX(c.CreationDate) AS LatestCommentDate,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN c.UserDisplayName IS NULL THEN 1 ELSE 0 END) AS AnonymousComments
    FROM Comments c
    GROUP BY c.PostId
),
PostDetails AS (
    SELECT
        p.Id,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        p.ClosedDate,
        p.Title,
        SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)) AS CleanedTags,
        pl.NumberOfLinks AS PostLinkCount,
        pl.LatestLinkDate,
        pl.LinkTypesUsed,
        ca.NumberOfComments AS CommentCountByCommentsTable,
        ca.AvgCommentScore,
        ca.AnonymousComments,
        ph.TotalEdits,
        ph.LastEditDate AS PostLastEditDate,
        rp.rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostLinkAnalysis pl ON p.Id = pl.PostId
    LEFT JOIN CommentAnalysis ca ON p.Id = ca.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS TotalEdits, MAX(CreationDate) AS LastEditDate
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    LEFT JOIN RankedPosts rp ON p.Id = rp.PostId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.LastAccessDate,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.HighScoreQuestionCount,
    ua.HighScoreAnswerCount,
    ua.AvgQuestionScore,
    ua.AvgAnswerScore,
    ua.TotalViews,
    ua.TotalFavorites,
    ua.TotalComments,
    ua.ClosedPostCount,
    ua.LatestPostDate,
    ua.RecentPostsCount,
    CASE
        WHEN ua.Reputation > 100000 THEN 'Legendary'
        WHEN ua.Reputation > 50000 THEN 'Titan'
        WHEN ua.Reputation > 10000 THEN 'Master'
        WHEN ua.Reputation > 1000 THEN 'Experienced'
        WHEN ua.Reputation > 100 THEN 'Novice'
        ELSE 'Beginner'
    END AS ReputationTier,
    pd.Id AS ExamplePostId,
    pd.PostTypeName,
    pd.CreationDate AS PostCreationDate,
    pd.Score AS PostScore,
    pd.ViewCount AS PostViewCount,
    pd.AnswerCount AS PostAnswerCount,
    pd.FavoriteCount AS PostFavoriteCount,
    pd.CommentCount AS PostCommentCount,
    pd.ClosedDate AS PostClosedDate,
    pd.Title AS PostTitle,
    pd.CleanedTags,
    pd.PostLinkCount,
    pd.LatestLinkDate,
    pd.LinkTypesUsed,
    pd.CommentCountByCommentsTable,
    pd.AvgCommentScore,
    pd.AnonymousComments,
    pd.TotalEdits AS PostTotalEdits,
    pd.PostLastEditDate,
    COALESCE(pd.ClosedDate, pd.CreationDate) AS EffectiveEndDate,
    LAG(pd.Score, 1, 0) OVER (PARTITION BY ua.UserId ORDER BY pd.CreationDate) AS PreviousPostScore,
    CASE WHEN pd.Score > LAG(pd.Score, 1, 0) OVER (PARTITION BY ua.UserId ORDER BY pd.CreationDate) THEN 'Improved' ELSE 'Not Improved' END AS ScoreTrend
FROM UserActivity ua
JOIN PostDetails pd ON ua.UserId = pd.OwnerUserId
WHERE pd.rn = 1
UNION
SELECT
    NULL AS UserId,
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS UserCreationDate,
    NULL AS LastAccessDate,
    NULL AS TotalPosts,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS HighScoreQuestionCount,
    NULL AS HighScoreAnswerCount,
    NULL AS AvgQuestionScore,
    NULL AS AvgAnswerScore,
    NULL AS TotalViews,
    NULL AS TotalFavorites,
    NULL AS TotalComments,
    NULL AS ClosedPostCount,
    NULL AS LatestPostDate,
    NULL AS RecentPostsCount,
    'Overall Summary' AS ReputationTier,
    NULL AS ExamplePostId,
    'Summary' AS PostTypeName,
    NULL AS PostCreationDate,
    AVG(pd.Score) AS PostScore,
    SUM(pd.ViewCount) AS PostViewCount,
    SUM(pd.AnswerCount) AS PostAnswerCount,
    SUM(pd.FavoriteCount) AS PostFavoriteCount,
    SUM(pd.CommentCount) AS PostCommentCount,
    NULL AS PostClosedDate,
    NULL AS PostTitle,
    NULL AS CleanedTags,
    COUNT(pd.PostLinkCount) AS PostLinkCount,
    MAX(pd.LatestLinkDate) AS LatestLinkDate,
    NULL AS LinkTypesUsed,
    SUM(pd.CommentCountByCommentsTable) AS CommentCountByCommentsTable,
    AVG(pd.AvgCommentScore) AS AvgCommentScore,
    SUM(pd.AnonymousComments) AS AnonymousComments,
    SUM(pd.TotalEdits) AS PostTotalEdits,
    MAX(pd.PostLastEditDate) AS PostLastEditDate,
    NULL AS EffectiveEndDate,
    NULL AS PreviousPostScore,
    NULL AS ScoreTrend
FROM PostDetails pd
WHERE pd.OwnerUserId IS NULL OR pd.OwnerUserId = 0;