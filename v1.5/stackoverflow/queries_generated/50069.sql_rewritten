-- {"query": "50069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 997} 
WITH UserTier AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        CASE
            WHEN Reputation >= 100000 THEN 'Diamond Tier (100k+)'
            WHEN Reputation >= 50000 AND Reputation < 100000 THEN 'Platinum Tier (50k-100k)'
            WHEN Reputation >= 10000 AND Reputation < 50000 THEN 'Gold Tier (10k-50k)'
            ELSE 'Silver Tier (<10k)'
        END AS ReputationTier
    FROM Users
    WHERE LastAccessDate > (SELECT MAX(CreationDate) FROM Posts) - INTERVAL '3 year' AND Views > 0
),
PostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        AVG(p.CommentCount) AS AvgCommentCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.LastActivityDate) - MIN(p.CreationDate) AS ContributionLifespan,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)))
            FILTER (WHERE q.PostTypeId = 1 AND a.PostTypeId = 2) AS AvgTimeToAnswerSeconds
    FROM Posts p
    LEFT JOIN Posts q ON p.Id = q.Id AND q.PostTypeId = 1
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate > '2015-01-01'
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 20
),
EngagementRanking AS (
    SELECT
        ut.UserId,
        ut.DisplayName,
        ut.Reputation,
        ut.ReputationTier,
        ps.TotalPosts,
        ps.QuestionCount,
        ps.AnswerCount,
        ps.TotalScore,
        ps.TotalViewCount,
        ps.ContributionLifespan,
        ps.AvgTimeToAnswerSeconds,
        (
            SELECT STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC)
            FROM (
                SELECT Name, Date FROM Badges WHERE UserId = ut.UserId AND Class = 1 ORDER BY Date DESC LIMIT 3
            ) b
        ) AS RecentGoldBadges,
        (
            SELECT p_sub.Title
            FROM Posts p_sub
            WHERE p_sub.OwnerUserId = ut.UserId AND p_sub.PostTypeId = 1
            ORDER BY p_sub.Score DESC, p_sub.ViewCount DESC
            LIMIT 1
        ) AS TopQuestionTitle,
        DENSE_RANK() OVER(PARTITION BY ut.ReputationTier ORDER BY ps.TotalScore DESC, ps.TotalViewCount DESC) AS TierRank
    FROM UserTier ut
    JOIN PostStats ps ON ut.UserId = ps.OwnerUserId
    WHERE ps.AnswerCount > ps.QuestionCount AND ps.QuestionCount > 0
)
SELECT
    er.ReputationTier,
    er.TierRank,
    er.DisplayName,
    er.Reputation,
    er.TotalPosts,
    CAST(er.AnswerCount AS REAL) / er.TotalPosts AS AnswerRatio,
    er.TotalScore / er.TotalPosts AS ScorePerPost,
    er.TotalViewCount,
    er.ContributionLifespan,
    er.AvgTimeToAnswerSeconds,
    er.RecentGoldBadges,
    er.TopQuestionTitle
FROM EngagementRanking er
WHERE er.TierRank <= 10
ORDER BY
    CASE er.ReputationTier
        WHEN 'Diamond Tier (100k+)' THEN 1
        WHEN 'Platinum Tier (50k-100k)' THEN 2
        WHEN 'Gold Tier (10k-50k)' THEN 3
        WHEN 'Silver Tier (<10k)' THEN 4
    END,
    er.TierRank;