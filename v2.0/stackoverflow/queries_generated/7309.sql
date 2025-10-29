-- {"query": "7309.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1960} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
        COALESCE(MAX(p.CreationDate), u.CreationDate) as LastActivityDate,
        MAX(p.ViewCount) as MaxViewCount,
        MAX(p.FavoriteCount) as MaxFavoriteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) as TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as BronzeBadges,
        STRING_AGG(b.Name, ', ') as BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
UserActivityStats AS (
    SELECT 
        ph.UserId,
        COUNT(*) as TotalEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN ph.PostId END) as TitleBodyTagEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.PostId END) as StatusChanges,
        MAX(ph.CreationDate) as LastEditDate,
        MIN(ph.CreationDate) as FirstEditDate,
        DATEDIFF(DAY, MIN(ph.CreationDate), MAX(ph.CreationDate)) as EditTimeSpanDays
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TagStatistics AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        p.Title as WikiTitle,
        p.Body as WikiBody,
        p.Score as WikiScore,
        RANK() OVER (ORDER BY t.Count DESC) as TagRank,
        NTILE(10) OVER (ORDER BY t.Count DESC) as TagDecile
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
),
TopUsers AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.Questions,
        ups.Answers,
        ups.TotalQuestionScore,
        ups.TotalAnswerScore,
        ups.AvgQuestionScore,
        ups.AvgAnswerScore,
        ups.LastActivityDate,
        ups.MaxViewCount,
        ups.MaxFavoriteCount,
        ubc.TotalBadges,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.BadgeNames,
        uas.TotalEdits,
        uas.TitleBodyTagEdits,
        uas.StatusChanges,
        uas.LastEditDate,
        uas.FirstEditDate,
        uas.EditTimeSpanDays,
        CASE 
            WHEN ups.Reputation > 10000 THEN 'Elite'
            WHEN ups.Reputation > 5000 THEN 'Veteran'
            WHEN ups.Reputation > 1000 THEN 'Active'
            ELSE 'Newbie'
        END as UserTier,
        CASE 
            WHEN ubc.TotalBadges >= 50 THEN 'Legendary'
            WHEN ubc.TotalBadges >= 25 THEN 'Master'
            WHEN ubc.TotalBadges >= 10 THEN 'Expert'
            ELSE 'Regular'
        END as BadgeTier
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubc ON ups.UserId = ubc.UserId
    LEFT JOIN UserActivityStats uas ON ups.UserId = uas.UserId
    WHERE ups.TotalPosts >= 10
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    tu.TotalQuestionScore,
    tu.TotalAnswerScore,
    tu.AvgQuestionScore,
    tu.AvgAnswerScore,
    tu.LastActivityDate,
    tu.MaxViewCount,
    tu.MaxFavoriteCount,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.BadgeNames,
    tu.TotalEdits,
    tu.TitleBodyTagEdits,
    tu.StatusChanges,
    tu.LastEditDate,
    tu.FirstEditDate,
    tu.EditTimeSpanDays,
    tu.UserTier,
    tu.BadgeTier,
    COALESCE(
        CASE 
            WHEN tu.TotalAnswerScore > 0 THEN (tu.TotalQuestionScore * 100.0 / tu.TotalAnswerScore)
            ELSE NULL 
        END, 
        0
    ) as QuestionToAnswerScoreRatio,
    CASE 
        WHEN tu.UserTier = 'Elite' AND tu.BadgeTier = 'Legendary' THEN 'Highly Influential'
        WHEN tu.UserTier IN ('Veteran', 'Active') AND tu.BadgeTier IN ('Master', 'Expert') THEN 'Respected Contributor'
        ELSE 'Regular Member'
    END as UserRole,
    STUFF((
        SELECT ', ' + ts.TagName
        FROM Posts p
        JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
        JOIN TagStatistics ts ON t.Id = ts.Id
        WHERE p.OwnerUserId = tu.UserId
        AND ts.TagRank <= 5
        GROUP BY ts.TagName
        ORDER BY ts.TagCount DESC
        FOR XML PATH('')
    ), 1, 2, '') as TopTags,
    LAG(tu.Reputation) OVER (ORDER BY tu.Reputation DESC) - tu.Reputation as ReputationDifference,
    ROW_NUMBER() OVER (ORDER BY tu.Reputation DESC) as ReputationRank,
    PERCENT_RANK() OVER (ORDER BY tu.Reputation) as ReputationPercentile,
    NTILE(4) OVER (ORDER BY tu.Reputation) as ReputationQuartile,
    DENSE_RANK() OVER (ORDER BY tu.TotalPosts DESC) as PostRank,
    COALESCE(
        (SELECT STRING_AGG(CONCAT('Q', p.Id), ', ') 
         FROM Posts p 
         WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 1 
         ORDER BY p.CreationDate DESC 
         LIMIT 5), 
        ''
    ) as RecentQuestions
FROM TopUsers tu
WHERE tu.Reputation >= (
    SELECT AVG(Reputation) * 1.5 
    FROM Users 
    WHERE Reputation > 0
)
AND (
    tu.Questions > 0 OR tu.Answers > 0 OR tu.TotalBadges > 0 OR tu.TotalEdits > 0
)
AND tu.UserId NOT IN (
    SELECT UserId 
    FROM Posts 
    WHERE PostTypeId = 1 
    AND OwnerUserId IS NULL
    AND CreationDate > '2022-01-01'
)
ORDER BY tu.Reputation DESC, tu.TotalPosts DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY
UNION ALL
SELECT 
    -1 as UserId,
    'System' as DisplayName,
    0 as Reputation,
    0 as TotalPosts,
    0 as Questions,
    0 as Answers,
    0 as TotalQuestionScore,
    0 as TotalAnswerScore,
    0 as AvgQuestionScore,
    0 as AvgAnswerScore,
    NULL as LastActivityDate,
    0 as MaxViewCount,
    0 as MaxFavoriteCount,
    0 as TotalBadges,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    NULL as BadgeNames,
    0 as TotalEdits,
    0 as TitleBodyTagEdits,
    0 as StatusChanges,
    NULL as LastEditDate,
    NULL as FirstEditDate,
    0 as EditTimeSpanDays,
    'System' as UserTier,
    'System' as BadgeTier,
    0 as QuestionToAnswerScoreRatio,
    'System' as UserRole,
    NULL as TopTags,
    0 as ReputationDifference,
    0 as ReputationRank,
    0 as ReputationPercentile,
    0 as ReputationQuartile,
    0 as PostRank,
    NULL as RecentQuestions
WHERE EXISTS (
    SELECT 1 
    FROM Users 
    WHERE Reputation > 10000
)
ORDER BY Reputation DESC;