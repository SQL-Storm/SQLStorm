WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.UserDisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
FrequentEditors AS (
    SELECT
        rpe.UserId,
        rpe.UserDisplayName,
        COUNT(DISTINCT rpe.PostId) AS DistinctPostsEdited,
        MAX(rpe.EditDate) AS LastEditDate
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
    GROUP BY rpe.UserId, rpe.UserDisplayName
    HAVING COUNT(DISTINCT rpe.PostId) > 5
),
PostPerformance AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostType,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        u.DisplayName AS OwnerDisplayName,
        CASE
            WHEN pf.UserId IS NOT NULL THEN 'FrequentEditor'
            ELSE 'Other'
        END AS EditorStatus,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementMetrics,
        CASE
            WHEN p.Score > 100 AND p.FavoriteCount > 50 THEN 'HighEngagement'
            WHEN p.Score > 50 AND p.ViewCount > 1000 THEN 'Popular'
            WHEN p.AnswerCount > 10 THEN 'Active'
            ELSE 'Standard'
        END AS PostCategory,
        CAST(EXTRACT(YEAR FROM p.CreationDate) AS VARCHAR) || '-' ||
        LPAD(CAST(EXTRACT(WEEK FROM p.CreationDate) AS INTEGER)::TEXT, 2, '0') AS YearWeek
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN FrequentEditors pf ON u.Id = pf.UserId
    WHERE p.PostTypeId IN (1, 2)
),
UserScoreDistribution AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Votes
    WHERE VoteTypeId IN (2, 3, 5)
    GROUP BY PostId
)
SELECT
    pp.PostId,
    pp.Title,
    pp.PostType,
    pp.CreationDate,
    pp.Score,
    pp.ViewCount,
    pp.AnswerCount,
    pp.CommentCount,
    pp.FavoriteCount,
    pp.PostStatus,
    pp.OwnerDisplayName,
    pp.EditorStatus,
    pp.EngagementMetrics,
    pp.PostCategory,
    pp.YearWeek,
    COALESCE(usd.UpVotes, 0) AS TotalUpVotes,
    COALESCE(usd.DownVotes, 0) AS TotalDownVotes,
    CASE
        WHEN usd.UpVotes IS NULL THEN 'No Votes'
        WHEN usd.UpVotes > usd.DownVotes * 2 THEN 'StronglyPositive'
        WHEN usd.DownVotes > usd.UpVotes * 2 THEN 'StronglyNegative'
        ELSE 'MixedOrNeutral'
    END AS VoteSentiment,
    u_contrib.TotalPostsOwned,
    u_contrib.QuestionCount,
    u_contrib.AnswerCount,
    u_contrib.AveragePostScore,
    u_contrib.BadgeCount,
    u_contrib.GoldBadgeCount,
    u_contrib.SilverBadgeCount,
    u_contrib.BronzeBadgeCount,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = pp.PostId
        AND c.UserId = (SELECT Id FROM Users WHERE DisplayName = pp.OwnerDisplayName)
    ) AS OwnerCommentCount,
    (
        SELECT COUNT(*)
        FROM (
            SELECT PostId, CreationDate FROM PostHistory WHERE PostHistoryTypeId = 4
            UNION ALL
            SELECT PostId, CreationDate FROM PostHistory WHERE PostHistoryTypeId = 5
            UNION ALL
            SELECT PostId, CreationDate FROM PostHistory WHERE PostHistoryTypeId = 6
        ) AS CombinedEdits
        WHERE CombinedEdits.PostId = pp.PostId
    ) AS TotalBodyOrTitleOrTagEdits
FROM PostPerformance pp
LEFT JOIN UserScoreDistribution usd ON pp.PostId = usd.PostId
LEFT JOIN UserContributionSummary u_contrib ON pp.OwnerDisplayName = u_contrib.DisplayName
WHERE pp.Score > 0 AND pp.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
ORDER BY pp.Score DESC, pp.ViewCount DESC
LIMIT 100;