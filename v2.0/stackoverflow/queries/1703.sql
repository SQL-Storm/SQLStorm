WITH UserPostTagStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AveragePostScore,
        SUM(p.ViewCount) AS TotalPostViews,
        MAX(p.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT t.tag_value) AS DistinctRelevantTags,
        MAX(CASE WHEN LOWER(p.Tags) LIKE '%<sql>%' THEN 1 ELSE 0 END) AS HasSqlPosts,
        MAX(CASE WHEN LOWER(p.Tags) LIKE '%<performance>%' THEN 1 ELSE 0 END) AS HasPerformancePosts
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL (SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag_value) t
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.OwnerUserId IS NOT NULL
        AND LOWER(t.tag_value) IN ('sql', 'performance')
    GROUP BY p.OwnerUserId, u.DisplayName, u.Reputation, u.CreationDate
),
UserEditAndCommentActivity AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS TotalCloseDeleteVotes,
        MAX(ph.CreationDate) AS LastEditDate,
        (
            SELECT COUNT(c.Id)
            FROM Comments c
            WHERE c.UserId = ph.UserId
        ) AS TotalCommentsMade
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
UserBadgeVoteSummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (
            SELECT COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0)
            FROM Votes v
            JOIN Posts p ON v.PostId = p.Id
            WHERE p.OwnerUserId = u.Id AND v.VoteTypeId IN (2, 3)
        ) AS NetVotesReceivedOnPosts,
        (
            SELECT COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0)
            FROM Votes v
            WHERE v.UserId = u.Id AND v.VoteTypeId IN (2, 3)
        ) AS NetVotesGiven
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
CombinedUserPerformance AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(ups.AveragePostScore, 0.0) AS AveragePostScore,
        COALESCE(ups.TotalPostViews, 0) AS TotalPostViews,
        COALESCE(ups.LastPostActivity, u.LastAccessDate) AS EffectiveLastActivity,
        COALESCE(ups.DistinctRelevantTags, 0) AS DistinctRelevantTags,
        COALESCE(ueca.TotalEdits, 0) AS TotalEdits,
        COALESCE(ueca.TotalCommentsMade, 0) AS TotalCommentsMade,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.NetVotesReceivedOnPosts, 0) AS NetVotesReceivedOnPosts,
        COALESCE(ubs.NetVotesGiven, 0) AS NetVotesGiven,
        (
            (COALESCE(ups.AveragePostScore, 0.0) * COALESCE(ups.TotalPosts, 0.0) * 1000)
            + COALESCE(ups.TotalPostViews, 0)
            + (COALESCE(ueca.TotalEdits, 0) * 50)
            + (COALESCE(ueca.TotalCommentsMade, 0) * 10)
            + (COALESCE(ubs.GoldBadges, 0) * 500)
            + (COALESCE(ubs.SilverBadges, 0) * 200)
            + (COALESCE(ubs.BronzeBadges, 0) * 50)
            + (COALESCE(ubs.NetVotesReceivedOnPosts, 0) * 2)
        ) / (
            1 + EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - COALESCE(ups.LastPostActivity, u.LastAccessDate))) / (60 * 60 * 24 * 30.0)
        ) AS RawEngagementScore,
        COALESCE(ups.HasSqlPosts, 0) AS HasSqlPosts,
        COALESCE(ups.HasPerformancePosts, 0) AS HasPerformancePosts
    FROM Users u
    LEFT JOIN UserPostTagStats ups ON u.Id = ups.UserId
    LEFT JOIN UserEditAndCommentActivity ueca ON u.Id = ueca.UserId
    LEFT JOIN UserBadgeVoteSummary ubs ON u.Id = ubs.UserId
    WHERE
        u.Reputation > 100
        AND (COALESCE(ups.HasSqlPosts, 0) = 1 OR COALESCE(ups.HasPerformancePosts, 0) = 1)
),
-- compute reputation quintile first as a column so other window functions can partition by it without nesting
RankedAndCategorizedUsersWithQuintile AS (
    SELECT
        cu.UserId,
        cu.DisplayName,
        cu.Reputation,
        cu.UserCreationDate,
        cu.LastAccessDate,
        cu.TotalPosts,
        cu.TotalPostScore,
        cu.AveragePostScore,
        cu.TotalPostViews,
        cu.EffectiveLastActivity,
        cu.DistinctRelevantTags,
        cu.TotalEdits,
        cu.TotalCommentsMade,
        cu.GoldBadges,
        cu.SilverBadges,
        cu.BronzeBadges,
        cu.NetVotesReceivedOnPosts,
        cu.NetVotesGiven,
        cu.RawEngagementScore,
        cu.HasSqlPosts,
        cu.HasPerformancePosts,
        RANK() OVER (ORDER BY cu.RawEngagementScore DESC, cu.Reputation DESC) AS GlobalEngagementRank,
        NTILE(5) OVER (ORDER BY cu.Reputation DESC) AS ReputationQuintile
    FROM CombinedUserPerformance cu
    WHERE cu.RawEngagementScore IS NOT NULL AND cu.RawEngagementScore > 0
),
RankedAndCategorizedUsers AS (
    SELECT
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.UserCreationDate,
        r.LastAccessDate,
        r.TotalPosts,
        r.TotalPostScore,
        r.AveragePostScore,
        r.TotalPostViews,
        r.EffectiveLastActivity,
        r.DistinctRelevantTags,
        r.TotalEdits,
        r.TotalCommentsMade,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        r.NetVotesReceivedOnPosts,
        r.NetVotesGiven,
        r.RawEngagementScore,
        r.HasSqlPosts,
        r.HasPerformancePosts,
        r.GlobalEngagementRank,
        r.ReputationQuintile,
        RANK() OVER (PARTITION BY r.ReputationQuintile ORDER BY r.RawEngagementScore DESC) AS QuintileEngagementRank,
        LAG(r.RawEngagementScore, 1, 0.0) OVER (ORDER BY r.RawEngagementScore DESC) AS PreviousEngagementScore,
        AVG(r.RawEngagementScore) OVER (PARTITION BY r.ReputationQuintile) AS AvgEngagementInQuintile
    FROM RankedAndCategorizedUsersWithQuintile r
),
FinalUserFocusSelection AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        GlobalEngagementRank,
        QuintileEngagementRank,
        RawEngagementScore,
        'SQL' AS FocusArea,
        HasSqlPosts,
        HasPerformancePosts
    FROM RankedAndCategorizedUsers
    WHERE HasSqlPosts = 1 AND HasPerformancePosts = 0
      AND QuintileEngagementRank <= 10

    UNION ALL

    SELECT
        UserId,
        DisplayName,
        Reputation,
        GlobalEngagementRank,
        QuintileEngagementRank,
        RawEngagementScore,
        'Performance' AS FocusArea,
        HasSqlPosts,
        HasPerformancePosts
    FROM RankedAndCategorizedUsers
    WHERE HasPerformancePosts = 1 AND HasSqlPosts = 0
      AND QuintileEngagementRank <= 10

    UNION ALL

    SELECT
        UserId,
        DisplayName,
        Reputation,
        GlobalEngagementRank,
        QuintileEngagementRank,
        RawEngagementScore,
        'Both' AS FocusArea,
        HasSqlPosts,
        HasPerformancePosts
    FROM RankedAndCategorizedUsers
    WHERE HasSqlPosts = 1 AND HasPerformancePosts = 1
      AND QuintileEngagementRank <= 5
)
SELECT
    fu.UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.FocusArea,
    CASE
        WHEN fu.FocusArea = 'Both' THEN 'Omni-Contributor'
        WHEN fu.FocusArea = 'SQL' THEN CONCAT('SQL Master (Rank: ', fu.QuintileEngagementRank, ')')
        WHEN fu.FocusArea = 'Performance' THEN CONCAT('Perf Guru (Rank: ', fu.QuintileEngagementRank, ')')
        ELSE 'Unknown Niche'
    END AS UserLabel,
    fu.GlobalEngagementRank,
    r.ReputationQuintile,
    fu.QuintileEngagementRank,
    fu.RawEngagementScore,
    r.TotalPosts,
    r.AveragePostScore,
    r.TotalEdits,
    r.GoldBadges,
    r.NetVotesReceivedOnPosts,
    NULLIF(
        ROUND(
            (CAST(r.NetVotesReceivedOnPosts AS NUMERIC) / NULLIF(r.TotalPosts, 0) + r.AveragePostScore) *
            (1 + (r.GoldBadges + r.SilverBadges) * 0.1)
        , 2), 0
    ) AS AdjustedImpactScore,
    r.PreviousEngagementScore,
    r.AvgEngagementInQuintile,
    (
        SELECT p.Title
        FROM Posts p
        WHERE p.OwnerUserId = fu.UserId
          AND p.PostTypeId = 1
          AND LOWER(p.Tags) LIKE ('%<' || LOWER(fu.FocusArea) || '>%')
        ORDER BY p.Score DESC, p.CreationDate DESC
        LIMIT 1
    ) AS TopPostTitleInFocus
FROM FinalUserFocusSelection fu
INNER JOIN RankedAndCategorizedUsers r
    ON fu.UserId = r.UserId
WHERE
    fu.GlobalEngagementRank <= 150
    AND r.ReputationQuintile IN (1, 2)
ORDER BY fu.UserId,
         CASE WHEN fu.FocusArea = 'Both' THEN 1
              WHEN fu.FocusArea = 'SQL' THEN 2
              WHEN fu.FocusArea = 'Performance' THEN 3
              ELSE 4 END
LIMIT 50;