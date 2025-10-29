WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_user_post_type,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.OwnerUserId) AS avg_user_score,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS total_user_views,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS previous_post_score,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(rp.PostCreationDate) AS LastPostDate,
        MAX(rp.PostScore) AS MaxPostScore,
        MIN(rp.PostScore) AS MinPostScore,
        AVG(rp.PostScore) AS AvgPostScore,
        SUM(rp.PostViewCount) AS TotalPostViews,
        COUNT(DISTINCT CASE WHEN rp.IsClosed = 1 THEN rp.PostId ELSE NULL END) AS ClosedPostCount,
        COUNT(DISTINCT CASE WHEN rp.PostTypeName = 'Question' THEN rp.PostId ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN rp.PostTypeName = 'Answer' THEN rp.PostId ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN rp.PostTypeName = 'Question' THEN rp.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
        SUM(CASE WHEN rp.PostTypeName = 'Question' THEN rp.CommentCount ELSE 0 END) AS TotalCommentsOnQuestions,
        AVG(CASE WHEN rp.PostTypeName = 'Question' THEN rp.PostScore ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN rp.PostTypeName = 'Answer' THEN rp.PostScore ELSE NULL END) AS AvgAnswerScore,
        MAX(rp.rn_user_post_type) AS MaxRankForAnyPostType,
        COUNT(DISTINCT rp.PostId) AS TotalPosts
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostId = rp.PostId
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.PostId = rp.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
TagPerformance AS (
    SELECT
        t.TagName,
        SUM(rp.PostScore) AS TotalScore,
        COUNT(DISTINCT rp.PostId) AS PostCount,
        AVG(rp.PostScore) AS AvgScore,
        SUM(rp.PostViewCount) AS TotalViews,
        AVG(rp.FavoriteCount) AS AvgFavoriteCount,
        SUM(CASE WHEN rp.IsClosed = 1 THEN 1 ELSE 0 END) AS ClosedPosts,
        STRING_AGG(DISTINCT rp.PostTypeName, ', ') AS PostTypesPresent
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN RankedPosts rp ON p.Id = rp.PostId
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT rp.PostId) > 10
),
UserTagPerformance AS (
    SELECT
        ua.UserId,
        tp.TagName,
        COUNT(DISTINCT rp.PostId) AS UserPostsForTag,
        SUM(rp.PostScore) AS UserScoreForTag,
        AVG(rp.PostScore) AS UserAvgScoreForTag
    FROM UserActivity ua
    JOIN RankedPosts rp ON ua.UserId = rp.OwnerUserId
    JOIN Posts p ON rp.PostId = p.Id
    JOIN Tags tp ON p.Tags LIKE '%' || tp.TagName || '%'
    WHERE tp.TagName IN (SELECT TagName FROM TagPerformance)
    GROUP BY ua.UserId, tp.TagName
    HAVING COUNT(DISTINCT rp.PostId) > 2
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.UserViews,
    ua.UserUpVotes,
    ua.UserDownVotes,
    ua.PostHistoryCount,
    ua.EditCount,
    ua.CommentCount,
    ua.LastPostDate,
    ua.MaxPostScore,
    ua.MinPostScore,
    ua.AvgPostScore,
    ua.TotalPostViews,
    ua.ClosedPostCount,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalAnswersToQuestions,
    ua.TotalCommentsOnQuestions,
    ua.AvgQuestionScore,
    ua.AvgAnswerScore,
    ua.TotalPosts,
    rp.PostTypeName AS MostRecentPostType,
    rp.PostScore AS MostRecentPostScore,
    rp.PostViewCount AS MostRecentPostViewCount,
    tp.TagName AS TopTag,
    tp.AvgScore AS TopTagAvgScore,
    tp.TotalViews AS TopTagTotalViews,
    COALESCE(utp.UserAvgScoreForTag, 0) AS UserAvgScoreForTopTag,
    (ua.UserUpVotes + ua.UserDownVotes) AS TotalVotesCast,
    CASE WHEN ua.UserViews > 0 THEN CAST(ua.TotalPostViews AS DOUBLE PRECISION) / ua.UserViews ELSE 0 END AS ViewToTotalViewRatio,
    CASE WHEN ua.UserCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Older' ELSE 'Newer' END AS UserAgeCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 3) AS BronzeBadgeCount,
    CASE WHEN ua.AvgPostScore > (SELECT AVG(AvgScore) FROM TagPerformance) THEN 'Above Avg Tag Score' ELSE 'Below Avg Tag Score' END AS UserScoreVsTagAvg,
    (ua.TotalPostViews * ua.Reputation) AS WeightedViewScore
FROM UserActivity ua
LEFT JOIN RankedPosts rp ON ua.UserId = rp.OwnerUserId AND rp.rn_user_post_type = 1
LEFT JOIN UserTagPerformance utp ON ua.UserId = utp.UserId
LEFT JOIN TagPerformance tp ON utp.TagName = tp.TagName
WHERE ua.TotalPosts > 5
ORDER BY ua.Reputation DESC
LIMIT 100;