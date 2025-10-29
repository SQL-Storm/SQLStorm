-- {"query": "7816.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2132} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(v.CreationDate) as LastVoteDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                (COUNT(DISTINCT p.Id) * 100.0) / NULLIF((SELECT COUNT(*) FROM Posts), 0)
            ELSE 0 
        END as PostPercentage,
        CASE 
            WHEN COUNT(DISTINCT v.Id) > 0 THEN 
                AVG(v.CreationDate - p.CreationDate) 
            ELSE NULL 
        END as AvgTimeToVote,
        STRING_AGG(DISTINCT p.PostTypeId::text, ',') as PostTypesUsed
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01 00:00:00'::timestamp
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) + COUNT(DISTINCT b.Id) > 0
),
PostPerformanceMetrics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (p.Score * 100.0) / NULLIF(p.ViewCount, 0)
            ELSE 
                (p.Score * 1000.0) / NULLIF(p.ViewCount, 0)
        END as EngagementRate,
        CASE 
            WHEN p.Score > 0 THEN 
                (p.AnswerCount * 100.0) / NULLIF(p.Score, 0)
            ELSE 
                0 
        END as AnswerScoreRatio,
        p.Tags,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') as TagArray,
        (p.Score + COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0)) as CombinedScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2010-01-01 00:00:00'::timestamp
      AND p.Score > -5
),
UserComplexityAnalysis AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as MaxQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as MaxAnswerScore,
        STDEV(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as StdDevQuestionScore,
        STDEV(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as StdDevAnswerScore,
        (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0) / 
        NULLIF(COUNT(DISTINCT p.Id), 0) as QuestionPercentage
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2010-01-01 00:00:00'::timestamp
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 0
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.PostCount,
    uas.CommentCount,
    uas.BadgeCount,
    uas.VoteCount,
    uas.PostPercentage,
    uas.AvgTimeToVote,
    uas.PostTypesUsed,
    ppo.PostId,
    ppo.Title,
    ppo.Score,
    ppo.ViewCount,
    ppo.AnswerCount,
    ppo.CommentCount,
    ppo.CreationDate,
    ppo.PostTypeId,
    ppo.EngagementRate,
    ppo.AnswerScoreRatio,
    ppo.TagArray,
    ppo.CombinedScore,
    ppo.UserPostRank,
    ppo.GlobalScoreRank,
    uca.QuestionCount,
    uca.AnswerCount,
    uca.AvgQuestionScore,
    uca.AvgAnswerScore,
    uca.MaxQuestionScore,
    uca.MaxAnswerScore,
    uca.StdDevQuestionScore,
    uca.StdDevAnswerScore,
    uca.QuestionPercentage,
    CASE 
        WHEN ppo.EngagementRate > 10.0 THEN 'Highly Engaging'
        WHEN ppo.EngagementRate > 5.0 THEN 'Moderately Engaging'
        WHEN ppo.EngagementRate > 1.0 THEN 'Low Engagement'
        ELSE 'Minimal Engagement'
    END as EngagementCategory,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = ppo.PostId 
              AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
              AND ph.CreationDate >= '2020-01-01 00:00:00'::timestamp
        ) THEN 'Active Mod History'
        ELSE 'No Active Mod History'
    END as ModHistoryStatus,
    COALESCE(SUM(ppo.Score) OVER (
        PARTITION BY uas.UserId 
        ORDER BY ppo.CreationDate 
        ROWS BETWEEN 10 PRECEDING AND CURRENT ROW
    ), 0) as RollingAvgScore,
    CASE 
        WHEN uas.PostCount > 100 AND uas.Reputation > 10000 THEN 'Veteran Contributor'
        WHEN uas.PostCount > 50 AND uas.Reputation > 5000 THEN 'Experienced Contributor'
        WHEN uas.PostCount > 10 AND uas.Reputation > 1000 THEN 'Active Contributor'
        ELSE 'New Contributor'
    END as ContributionTier,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uas.UserId AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uas.UserId AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uas.UserId AND b.Class = 3) as BronzeBadges,
    CASE 
        WHEN uas.Reputation > (SELECT AVG(Reputation) FROM Users WHERE CreationDate >= '2010-01-01 00:00:00'::timestamp) 
        THEN 'Above Average'
        WHEN uas.Reputation > 1000 THEN 'Average'
        ELSE 'Below Average'
    END as ReputationTier,
    DATE_TRUNC('month', ppo.CreationDate) as CreationMonth,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = uas.UserId AND p2.CreationDate >= '2021-01-01 00:00:00'::timestamp) as RecentPosts2021
FROM UserActivityStats uas
INNER JOIN PostPerformanceMetrics ppo ON uas.UserId = ppo.OwnerUserId
INNER JOIN UserComplexityAnalysis uca ON uas.UserId = uca.UserId
WHERE (uas.PostCount >= 5 OR uas.CommentCount >= 10 OR uas.BadgeCount >= 3 OR uas.VoteCount >= 20)
  AND (ppo.Score >= 10 OR ppo.ViewCount >= 100)
  AND (uca.QuestionCount > 0 OR uca.AnswerCount > 0)
  AND EXISTS (
    SELECT 1 FROM Posts p3 
    WHERE p3.OwnerUserId = uas.UserId 
      AND p3.CreationDate >= '2020-01-01 00:00:00'::timestamp
  )
  AND EXISTS (
    SELECT 1 FROM Votes v2 
    WHERE v2.UserId = uas.UserId 
      AND v2.CreationDate >= '2020-01-01 00:00:00'::timestamp
  )
  AND NOT EXISTS (
    SELECT 1 FROM PostHistory ph2 
    WHERE ph2.UserId = uas.UserId 
      AND ph2.PostHistoryTypeId = 12
      AND ph2.CreationDate >= '2020-01-01 00:00:00'::timestamp
  )
ORDER BY 
    uas.Reputation DESC,
    ppo.Score DESC,
    ppo.CreationDate DESC
LIMIT 500;