-- {"query": "18025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1391} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn_user_creation,
        RANK() OVER(ORDER BY p.Score DESC, p.ViewCount DESC) as rnk_score_view,
        DENSE_RANK() OVER(PARTITION BY p.PostTypeId ORDER BY p.FavoriteCount DESC) as dense_rnk_fav_posttype
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.Score > 0
),
UserPostActivity AS (
    SELECT
        rp.OwnerUserId,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(rp.Score) AS TotalScore,
        AVG(rp.ViewCount) AS AvgViewCount,
        MAX(rp.CreationDate) AS LastPostDate,
        STRING_AGG(rp.PostTypeName, ', ') AS PostTypesPosted
    FROM RankedPosts rp
    GROUP BY rp.OwnerUserId
    HAVING COUNT(rp.PostId) > 5
),
PostLagLead AS (
    SELECT
        rp.PostId,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.rnk_score_view,
        LAG(rp.Score, 1, 0) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) AS PreviousPostScore,
        LEAD(rp.Score, 1, 0) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) AS NextPostScore,
        rp.dense_rnk_fav_posttype
    FROM RankedPosts rp
    WHERE rp.rn_user_creation <= 10
),
TopUsers AS (
    SELECT
        upa.OwnerUserId,
        upa.TotalPosts,
        upa.TotalScore,
        upa.AvgViewCount,
        upa.PostTypesPosted,
        u.DisplayName AS UserDisplayName,
        u.Reputation AS UserReputation,
        CASE
            WHEN u.DownVotes > u.UpVotes * 10 THEN 'High Ratio Negative Votes'
            WHEN u.UpVotes > u.DownVotes * 10 THEN 'High Ratio Positive Votes'
            ELSE 'Balanced Votes'
        END AS VoteRatioCategory,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM UserPostActivity upa
    JOIN Users u ON upa.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
)
SELECT
    pll.PostId,
    pll.OwnerUserId,
    tu.UserDisplayName,
    tu.UserReputation,
    tu.VoteRatioCategory,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    pll.CreationDate,
    pll.Score AS CurrentPostScore,
    pll.PreviousPostScore,
    pll.NextPostScore,
    pll.ViewCount,
    pll.rnk_score_view,
    pll.dense_rnk_fav_posttype,
    CASE
        WHEN pll.Score > pll.PreviousPostScore AND pll.Score > pll.NextPostScore THEN 'Peak Score Post'
        WHEN pll.Score < pll.PreviousPostScore AND pll.Score < pll.NextPostScore THEN 'Trough Score Post'
        ELSE 'Average Score Post'
    END AS ScoreTrend,
    COALESCE(DATEDIFF(day, pll.CreationDate, pll.ClosedDate), -1) AS DaysToClose,
    CASE
        WHEN pll.Score * pll.ViewCount > 1000000 THEN 'High Engagement'
        WHEN pll.Score * pll.ViewCount < 1000 THEN 'Low Engagement'
        ELSE 'Medium Engagement'
    END AS EngagementLevel,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = pll.PostId AND c.Score > 5) AS HighScoreComments,
    (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = pll.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
    tu.TotalPosts AS UserTotalPosts,
    tu.TotalScore AS UserTotalScore,
    tu.AvgViewCount AS UserAvgViewCount,
    tu.PostTypesPosted
FROM PostLagLead pll
JOIN TopUsers tu ON pll.OwnerUserId = tu.OwnerUserId
LEFT JOIN PostLinks pl ON pll.PostId = pl.PostId AND pl.LinkTypeId = 3
WHERE pll.Score > 50
UNION ALL
SELECT
    NULL,
    NULL,
    'Community User',
    0,
    'N/A',
    0,
    0,
    0,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'N/A',
    NULL,
    'N/A',
    0,
    0,
    NULL,
    NULL,
    NULL,
    NULL
WHERE NOT EXISTS (SELECT 1 FROM TopUsers);