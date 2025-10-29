WITH QuestionTagUsage AS (
    SELECT
        p.OwnerUserId AS UserId,
        TRIM(tag_name.value) AS Tag,
        p.Id AS PostId
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name(value)
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND LENGTH(TRIM(p.Tags)) > 2
      AND p.OwnerUserId IS NOT NULL
),
UserTopTags AS (
    SELECT
        qtu.UserId,
        qtu.Tag,
        COUNT(DISTINCT qtu.PostId) AS TaggedQuestionCount,
        ROW_NUMBER() OVER(PARTITION BY qtu.UserId ORDER BY COUNT(DISTINCT qtu.PostId) DESC, qtu.Tag ASC) AS rn
    FROM QuestionTagUsage qtu
    GROUP BY qtu.UserId, qtu.Tag
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT b_gold.Id) AS GoldBadges,
        COUNT(DISTINCT b_silver.Id) AS SilverBadges,
        COUNT(DISTINCT b_bronze.Id) AS BronzeBadges,
        u.UpVotes AS TotalUserUpVotes,
        u.DownVotes AS TotalUserDownVotes,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE NULL END) AS AvgContentScore,
        EXTRACT(DAY FROM (cast('2024-10-01' as date) - u.CreationDate)) + 365 * EXTRACT(YEAR FROM (cast('2024-10-01' as date) - u.CreationDate)) + 30 * EXTRACT(MONTH FROM (cast('2024-10-01' as date) - u.CreationDate)) AS DaysActive
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b_gold ON u.Id = b_gold.UserId AND b_gold.Class = 1
    LEFT JOIN Badges b_silver ON u.Id = b_silver.UserId AND b_silver.Class = 2
    LEFT JOIN Badges b_bronze ON u.Id = b_bronze.UserId AND b_bronze.Class = 3
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS CurrentPostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS CurrentCommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseVoteCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenVoteCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN ph.Id END) AS MigrationEventCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
RecentPostActivity AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS RecentCommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS RecentUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS RecentDownVotes
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.CreationDate > (p.CreationDate + INTERVAL '30 days')
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.CreationDate > (p.CreationDate + INTERVAL '30 days') AND v.VoteTypeId IN (2,3)
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
)
SELECT
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalComments,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    COALESCE(uas.AvgContentScore, 0.0) AS AvgContentScore,
    ROUND(CAST(uas.TotalUserUpVotes AS NUMERIC) / NULLIF(uas.TotalUserUpVotes + uas.TotalUserDownVotes, 0), 4) AS UserUpVoteRatio,
    uas.DaysActive,
    SUM(phm.CurrentPostScore) AS SumOfPostScores,
    SUM(phm.ViewCount) AS SumOfPostViews,
    SUM(phm.EditCount) AS TotalEditsAcrossPosts,
    SUM(phm.CloseVoteCount) AS TotalCloseVotesAcrossPosts,
    SUM(phm.ReopenVoteCount) AS TotalReopenVotesAcrossPosts,
    AVG(CASE WHEN phm.TotalUpVotes + phm.TotalDownVotes > 0 THEN CAST(phm.TotalUpVotes AS NUMERIC) / (phm.TotalUpVotes + phm.TotalDownVotes) ELSE 0.0 END) AS AvgPostUpVoteRatio,
    (SELECT Tag FROM UserTopTags WHERE UserId = uas.UserId AND rn = 1) AS TopTag1,
    (SELECT Tag FROM UserTopTags WHERE UserId = uas.UserId AND rn = 2) AS TopTag2,
    (SELECT Tag FROM UserTopTags WHERE UserId = uas.UserId AND rn = 3) AS TopTag3,
    LAG(uas.Reputation, 1, 0) OVER (ORDER BY uas.CreationDate, uas.UserId) AS PrevUserReputation,
    RANK() OVER (ORDER BY uas.Reputation DESC, uas.DaysActive ASC) AS GlobalReputationRank,
    NTILE(10) OVER (ORDER BY uas.TotalPosts DESC) AS PostCountDecile,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = uas.UserId AND p_sub.PostTypeId = 1)
          AND pl.LinkTypeId = 3
          AND pl.CreationDate > uas.CreationDate
    ) AS DuplicateLinkedPostsCount,
    (
        SELECT AVG(p_sub.FavoriteCount)
        FROM Posts p_sub
        WHERE p_sub.OwnerUserId = uas.UserId
          AND p_sub.PostTypeId = 1
          AND p_sub.FavoriteCount IS NOT NULL
          AND p_sub.CreationDate > (uas.CreationDate + INTERVAL '1 year')
    ) AS AvgQuestionFavoritesAfter1Yr,
    COALESCE(SUM(rpa.RecentCommentCount), 0) AS TotalRecentPostComments,
    COALESCE(SUM(rpa.RecentUpVotes), 0) AS TotalRecentPostUpVotes,
    NULLIF(TRIM(SUBSTRING(uas.DisplayName FROM 1 FOR 1)), '') AS FirstCharOfDisplayName,
    CASE
        WHEN uas.Reputation > 10000 AND uas.GoldBadges >= 5 THEN 'Elite Developer'
        WHEN uas.Reputation > 5000 AND uas.SilverBadges >= 10 THEN 'Experienced Contributor'
        WHEN uas.TotalQuestions > 50 AND COALESCE(uas.AvgContentScore, 0) > 10 THEN 'Prolific Questioner'
        WHEN uas.TotalAnswers > 100 AND COALESCE(uas.AvgContentScore, 0) > 15 THEN 'Reliable Answerer'
        ELSE 'Aspiring Member'
    END AS UserCategory,
    MD5(CAST(uas.UserId AS VARCHAR) || COALESCE(uas.DisplayName, '') || CAST(uas.Reputation AS VARCHAR) || CAST(uas.CreationDate AS VARCHAR) || CAST(uas.TotalPosts AS VARCHAR) || CAST(uas.TotalQuestions AS VARCHAR)) AS UserDataHash
FROM UserActivitySummary uas
LEFT JOIN PostHistoricalMetrics phm ON uas.UserId = phm.OwnerUserId
LEFT JOIN RecentPostActivity rpa ON uas.UserId = rpa.UserId
WHERE uas.Reputation > 1000
  AND uas.TotalPosts >= 5
  AND uas.DaysActive IS NOT NULL AND uas.DaysActive > 365
  AND (uas.DisplayName IS NOT NULL AND LENGTH(TRIM(uas.DisplayName)) > 0)
  AND (EXISTS (SELECT 1 FROM Badges b_any WHERE b_any.UserId = uas.UserId AND b_any.Class = 1))
  AND (NOT EXISTS (SELECT 1 FROM Posts p_closed WHERE p_closed.OwnerUserId = uas.UserId AND p_closed.ClosedDate IS NOT NULL AND p_closed.Score < 0))
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.CreationDate, uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers, uas.TotalComments,
    uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges, uas.TotalUserUpVotes, uas.TotalUserDownVotes, uas.AvgContentScore, uas.DaysActive
HAVING
    SUM(COALESCE(phm.EditCount, 0)) > 0 OR SUM(COALESCE(phm.CloseVoteCount, 0)) > 0 OR SUM(COALESCE(phm.ReopenVoteCount, 0)) > 0
ORDER BY
    GlobalReputationRank ASC,
    uas.TotalPosts DESC,
    TotalEditsAcrossPosts DESC NULLS LAST
LIMIT 100;