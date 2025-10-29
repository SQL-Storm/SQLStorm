-- {"query": "1288.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2834} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserGivenUpVotes,
        u.DownVotes AS UserGivenDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersPosted,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEvents,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate,
        COALESCE(AVG(p.Score), 0) AS AvgPostScoreOwned
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId
    LEFT JOIN Votes AS v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        CASE WHEN p.ViewCount > 0 THEN CAST(p.Score AS DECIMAL) / p.ViewCount ELSE 0 END AS ScorePerViewRatio,
        CASE WHEN p.ViewCount > 0 THEN CAST(COALESCE(p.AnswerCount, 0) AS DECIMAL) / p.ViewCount ELSE 0 END AS AnswerPerViewRatio,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesOnPost,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesOnPost,
        (SELECT c_inner.Text
         FROM Comments AS c_inner
         WHERE c_inner.PostId = p.Id
         ORDER BY c_inner.CreationDate DESC
         LIMIT 1) AS LatestCommentText,
        CASE
            WHEN p.Score > 50 AND p.LastActivityDate > (CURRENT_TIMESTAMP - INTERVAL '7 day') THEN 'Hot'
            WHEN p.Score < 0 AND p.ClosedDate IS NOT NULL THEN 'Controversial_Closed'
            WHEN p.ViewCount > 1000 AND p.AnswerCount IS NULL THEN 'HighView_NoAnswer'
            ELSE 'Normal'
        END AS PostEngagementCategory
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastActivityDate, p.ClosedDate
),
PostEditAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS TotalEditEvents,
        MIN(ph.CreationDate) AS FirstHistoryEventDate,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        EXTRACT(EPOCH FROM (MIN(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate END) - MIN(ph.CreationDate))) / 3600.0 AS HoursToFirstEdit,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE 0 END) AS RollbackCount,
        ARRAY_AGG(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS EditorUserIds
    FROM PostHistory AS ph
    GROUP BY ph.PostId
),
TagUsageStats AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(p.Id) AS TotalPostsWithTag,
        AVG(p.Score) AS AvgScoreForTagPosts,
        MAX(p.CreationDate) AS LatestPostWithTag,
        MIN(p.CreationDate) AS EarliestPostWithTag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScoreForTagPosts
    FROM Posts AS p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND length(p.Tags) > 2
    GROUP BY unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
),
UserBadgePerformance AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate,
        MIN(b.Date) AS EarliestBadgeDate
    FROM Badges AS b
    GROUP BY b.UserId
),
UserContentStream AS (
    SELECT
        p.Id AS ContentId,
        p.OwnerUserId AS UserId,
        p.CreationDate,
        'Question' AS ContentType,
        p.Title AS ContentTitle,
        p.Score AS ContentScore,
        p.ViewCount,
        p.AnswerCount,
        p.Tags
    FROM Posts AS p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL

    UNION ALL

    SELECT
        p.Id AS ContentId,
        p.OwnerUserId AS UserId,
        p.CreationDate,
        'Answer' AS ContentType,
        (SELECT q.Title FROM Posts q WHERE q.Id = p.ParentId) AS ContentTitle,
        p.Score AS ContentScore,
        NULL AS ViewCount,
        NULL AS AnswerCount,
        (SELECT q.Tags FROM Posts q WHERE q.Id = p.ParentId) AS Tags
    FROM Posts AS p
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
)
SELECT
    uas.UserId,
    uas.UserDisplayName,
    uas.Reputation,
    uas.TotalQuestionsAsked,
    uas.TotalAnswersPosted,
    uas.AvgPostScoreOwned,
    ubp.TotalBadges,
    ubp.GoldBadges,
    ubp.SilverBadges,
    pm.PostId,
    pm.PostTypeName,
    pm.Title,
    pm.PostCreationDate,
    pm.PostScore,
    pm.ViewCount,
    pm.ScorePerViewRatio,
    pm.AnswerPerViewRatio,
    pm.PostEngagementCategory,
    pea.TotalEditEvents,
    pea.HoursToFirstEdit,
    pea.RollbackCount,
    COALESCE(relevant_tag_stats.TagName, 'Untagged_or_NoQuestion') AS PrimaryTag,
    relevant_tag_stats.AvgScoreForTagPosts,
    relevant_tag_stats.MedianScoreForTagPosts,
    relevant_tag_stats.TotalPostsWithTag,
    RANK() OVER (ORDER BY uas.Reputation DESC) AS UserReputationRank,
    AVG(pm.PostScore) OVER (PARTITION BY uas.UserId ORDER BY pm.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserMovingAvgPostScore,
    LAG(pm.PostScore, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY pm.PostCreationDate) AS PreviousPostScore,
    pm.PostScore - LAG(pm.PostScore, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY pm.PostCreationDate) AS PostScoreDifference,
    CASE
        WHEN p_main.Tags IS NOT NULL AND length(p_main.Tags) > 2 THEN SUBSTRING(p_main.Tags, 2, POSITION('>' IN p_main.Tags) - 2)
        ELSE NULL
    END AS FirstTagInPost,
    pm.PostEngagementCategory = 'Hot' AND uas.Reputation > 5000 AND ubp.GoldBadges >= 1 AS IsEliteHotPostContributor,
    (pm.ClosedDate IS NOT NULL AND pm.TotalDownvotesOnPost > pm.TotalUpvotesOnPost) OR (pm.AnswerCount IS NULL AND pm.ViewCount > 5000 AND pm.PostTypeId = 1) AS IsProblematicPost,
    EXISTS (SELECT 1 FROM Comments c_inner WHERE c_inner.PostId = pm.PostId AND c_inner.UserId = uas.UserId) AS OwnerCommentedOnOwnPost,
    (SELECT COUNT(pl.Id) FROM PostLinks pl WHERE pl.PostId = pm.PostId OR pl.RelatedPostId = pm.PostId) AS RelatedPostCount,
    ucs.ContentType AS ContentStreamType,
    ucs.ContentTitle AS ContentStreamTitle
FROM UserActivitySummary AS uas
LEFT JOIN UserBadgePerformance AS ubp ON uas.UserId = ubp.UserId
RIGHT JOIN PostEngagementMetrics AS pm ON uas.UserId = pm.OwnerUserId
LEFT JOIN PostEditAnalysis AS pea ON pm.PostId = pea.PostId
LEFT JOIN Posts AS p_main ON pm.PostId = p_main.Id
LEFT JOIN LATERAL (
    SELECT
        tstats_inner.TagName,
        tstats_inner.AvgScoreForTagPosts,
        tstats_inner.MedianScoreForTagPosts,
        tstats_inner.TotalPostsWithTag
    FROM TagUsageStats AS tstats_inner
    WHERE p_main.Tags IS NOT NULL
      AND EXISTS (SELECT 1 FROM unnest(string_to_array(substring(p_main.Tags, 2, length(p_main.Tags)-2), '><')) AS post_tag WHERE post_tag = tstats_inner.TagName)
    ORDER BY tstats_inner.TotalPostsWithTag DESC
    LIMIT 1
) AS relevant_tag_stats ON TRUE
LEFT JOIN UserContentStream AS ucs ON pm.PostId = ucs.ContentId AND pm.OwnerUserId = ucs.UserId
WHERE
    uas.Reputation > 500
    AND pm.PostCreationDate BETWEEN '2021-01-01' AND CURRENT_TIMESTAMP - INTERVAL '30 day'
    AND pm.PostTypeName IN ('Question', 'Answer')
    AND (pm.Title LIKE '%SQL%' OR p_main.Body ILIKE '%index%' OR p_main.Tags ILIKE '%<database>%')
    AND pm.ScorePerViewRatio IS NOT NULL AND pm.ScorePerViewRatio > 0.001
    AND COALESCE(pea.RollbackCount, 0) < 3
ORDER BY
    UserReputationRank ASC,
    pm.PostScore DESC,
    pm.LastActivityDate DESC
LIMIT 1000;
