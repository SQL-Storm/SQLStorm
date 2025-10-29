-- {"query": "1034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3522}
WITH HighActivityPosts AS (
    SELECT
        Id,
        OwnerUserId,
        CreationDate,
        'RecentHighScore' AS ActivityCategory
    FROM Posts
    WHERE CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
      AND Score > 50
      AND PostTypeId = 1
    UNION ALL
    SELECT
        Id,
        OwnerUserId,
        CreationDate,
        'OldHighlyViewed' AS ActivityCategory
    FROM Posts
    WHERE CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
      AND ViewCount > 10000
      AND PostTypeId = 1
    UNION ALL
    SELECT
        Id,
        OwnerUserId,
        CreationDate,
        'HighlyFavoritedAnswer' AS ActivityCategory
    FROM Posts
    WHERE PostTypeId = 2
      AND FavoriteCount > 100
),
UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AvgPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnsweredQuestions,
        SUM(COALESCE(p.CommentCount, 0)) AS TotalPostComments,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavorites,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate,
        COUNT(DISTINCT hap.Id) AS HighActivityPostCount
    FROM Posts p
    LEFT JOIN HighActivityPosts hap ON p.Id = hap.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostAggregates AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.FavoriteCount,
        p.Title,
        p.Body,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBountyGiven,
        SUM(CASE WHEN v.VoteTypeId = 9 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBountyReceived,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseEventsCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenEventsCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 AND ph.Text LIKE '%<pre><code>%' THEN 1 ELSE 0 END) AS HasCodeBlockEdit
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 10, 11)
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.FavoriteCount, p.Title, p.Body, p.Tags, p.AcceptedAnswerId
),
UserPostWindowStats AS (
    SELECT
        pa.OwnerUserId AS UserId,
        pa.PostId,
        pa.PostCreationDate,
        pa.PostScore,
        pa.UpVotesReceived,
        pa.DownVotesReceived,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.PostCreationDate DESC) AS rn_latest_post,
        SUM(pa.PostScore) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativePostScore,
        AVG(pa.PostScore) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvgPostScore3Posts,
        MAX(pa.PostScore) OVER (PARTITION BY pa.OwnerUserId) AS MaxPostScoreEver,
        RANK() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.PostScore DESC) AS PostScoreRankByUser
    FROM PostAggregates pa
    WHERE pa.PostTypeId IN (1, 2)
),
UserTagFrequency AS (
    SELECT
        p.OwnerUserId AS UserId,
        qtu.TagName,
        COUNT(qtu.TagName) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(qtu.TagName) DESC, qtu.TagName ASC) AS rn_tag
    FROM Posts p
    JOIN LATERAL (
        SELECT TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName
    ) AS qtu ON TRUE
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, qtu.TagName
),
UserOverallMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.WebsiteUrl,
        u.AboutMe,
        u.UpVotes,
        u.DownVotes,
        COALESCE(ups.TotalPosts, 0) AS TotalPostsByOwner,
        COALESCE(ups.TotalQuestions, 0) AS TotalQuestionsByOwner,
        COALESCE(ups.TotalAnswers, 0) AS TotalAnswersByOwner,
        COALESCE(ups.TotalPostScore, 0) AS TotalPostScoreByOwner,
        COALESCE(ups.AvgPostScore, 0.0) AS AvgPostScoreByOwner,
        COALESCE(ups.HighActivityPostCount, 0) AS HighActivityPostCount,
        COALESCE(ucs.TotalComments, 0) AS TotalCommentsByOwner,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadgesCount,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadgesCount,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadgesCount,
        utf.TagName AS MostFrequentTag,
        utf.TagCount AS MostFrequentTagCount,
        MAX(pa.LastClosedDate) FILTER (WHERE pa.OwnerUserId = u.Id) AS LatestPostLastClosedDate,
        MAX(pa.LastReopenedDate) FILTER (WHERE pa.OwnerUserId = u.Id) AS LatestPostLastReopenedDate,
        SUM(pa.CloseEventsCount) FILTER (WHERE pa.OwnerUserId = u.Id) AS TotalCloseEventsOnUserPosts,
        SUM(pa.ReopenEventsCount) FILTER (WHERE pa.OwnerUserId = u.Id) AS TotalReopenEventsOnUserPosts,
        MAX(pa.HasCodeBlockEdit) FILTER (WHERE pa.OwnerUserId = u.Id) AS AnyPostHasCodeBlockEdit,
        MAX(CASE WHEN upws.rn_latest_post = 1 THEN upws.PostCreationDate ELSE NULL END) AS LatestPostCreationDate,
        MAX(CASE WHEN upws.rn_latest_post = 1 THEN upws.PostScore ELSE NULL END) AS LatestPostScore,
        MAX(upws.CumulativePostScore) AS CumulativeScoreOfAllPosts,
        MAX(upws.MovingAvgPostScore3Posts) AS LatestMovingAvgPostScore,
        MAX(upws.MaxPostScoreEver) AS HighestSinglePostScore,
        AVG(upws.UpVotesReceived) AS AvgUpVotesPerPostOwned,
        AVG(upws.DownVotesReceived) AS AvgDownVotesPerPostOwned
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    LEFT JOIN PostAggregates pa ON u.Id = pa.OwnerUserId
    LEFT JOIN UserPostWindowStats upws ON u.Id = upws.UserId
    LEFT JOIN UserTagFrequency utf ON u.Id = utf.UserId AND utf.rn_tag = 1
    WHERE
        u.Reputation > 500
        AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
        AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL OR u.AboutMe IS NOT NULL)
        AND NOT EXISTS (
            SELECT 1
            FROM Badges b_inner
            WHERE b_inner.UserId = u.Id
              AND b_inner.Name IN ('Generalist', 'Pundit', 'Disciplined')
        )
        AND u.Id NOT IN (
            SELECT DISTINCT p.OwnerUserId
            FROM Posts p
            WHERE p.Score < -5 AND p.PostTypeId IN (1, 2)
        )
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.WebsiteUrl, u.AboutMe, u.UpVotes, u.DownVotes,
        ups.TotalPosts, ups.TotalQuestions, ups.TotalAnswers, ups.TotalPostScore, ups.AvgPostScore, ups.HighActivityPostCount,
        ucs.TotalComments, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
        utf.TagName, utf.TagCount
    HAVING
        COUNT(DISTINCT pa.PostId) > 0
)
SELECT
    uom.UserId,
    uom.DisplayName,
    uom.Reputation,
    uom.UserCreationDate,
    uom.LastAccessDate,
    uom.Location,
    uom.TotalPostsByOwner,
    uom.TotalQuestionsByOwner,
    uom.TotalAnswersByOwner,
    uom.TotalPostScoreByOwner,
    uom.AvgPostScoreByOwner,
    uom.HighActivityPostCount,
    uom.TotalCommentsByOwner,
    uom.GoldBadgesCount,
    uom.SilverBadgesCount,
    uom.BronzeBadgesCount,
    (
        SELECT COUNT(p_inner.Id)
        FROM Posts p_inner
        WHERE p_inner.OwnerUserId = uom.UserId
          AND p_inner.PostTypeId = 1
          AND p_inner.FavoriteCount IS NOT NULL
          AND p_inner.FavoriteCount >= (
              SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId = 1 AND FavoriteCount IS NOT NULL
          )
    ) AS HighFavoriteQuestionsCount,
    (
        SELECT MAX(CASE WHEN p_inner.Title ILIKE '%sql%' OR p_inner.Body ILIKE '%database%' THEN 1 ELSE 0 END)
        FROM Posts p_inner
        WHERE p_inner.OwnerUserId = uom.UserId AND p_inner.PostTypeId = 1
    ) AS HasSQLRelatedQuestion,
    CASE
        WHEN uom.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(uom.WebsiteUrl)) > 0 THEN 'HasWebsite'
        WHEN uom.AboutMe IS NOT NULL AND LENGTH(TRIM(uom.AboutMe)) > 50 THEN 'VerboseAboutMe'
        ELSE 'MinimalProfile'
    END AS UserProfileCategory,
    uom.LatestPostLastClosedDate,
    uom.LatestPostLastReopenedDate,
    uom.TotalCloseEventsOnUserPosts,
    uom.TotalReopenEventsOnUserPosts,
    uom.AnyPostHasCodeBlockEdit,
    uom.MostFrequentTag,
    uom.MostFrequentTagCount,
    (
        SELECT COUNT(DISTINCT q_accepted.Id)
        FROM Posts q_accepted
        WHERE q_accepted.AcceptedAnswerId IN (
            SELECT p_ans.Id
            FROM Posts p_ans
            WHERE p_ans.OwnerUserId = uom.UserId AND p_ans.PostTypeId = 2
        )
    ) AS AnswersAcceptedByOthersCount,
    uom.LatestPostCreationDate,
    uom.LatestPostScore,
    uom.CumulativeScoreOfAllPosts,
    uom.LatestMovingAvgPostScore,
    uom.HighestSinglePostScore,
    uom.AvgUpVotesPerPostOwned,
    uom.AvgDownVotesPerPostOwned
FROM UserOverallMetrics uom
ORDER BY uom.Reputation DESC, uom.UserId;