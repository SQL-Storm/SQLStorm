-- {"query": "7355.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1819} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        COALESCE(p.Tags, '') as CleanTags,
        LENGTH(p.Tags) as TagLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(trim(p.Tags, '<>'), '><'), 1)
            ELSE 0 
        END as TagCount,
        (CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 1
            ELSE 0
        END) as HasRelatedPost,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) as DaysSinceLastActivity
    FROM Posts p
    WHERE p.CreationDate >= '2019-01-01'::timestamp
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        MIN(p.Score) as MinScore,
        COUNT(DISTINCT p.Tags) as TagVariety,
        (u.UpVotes - u.DownVotes) as NetVotes,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newbie'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as TagCategory
    FROM Tags t
    WHERE t.Count > 50
),
TagActivity AS (
    SELECT 
        pt.Id as PostId,
        pt.TagName,
        pt.Count,
        pt.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY pt.TagName ORDER BY pt.LastActivityDate DESC) as RecentActivity,
        LAG(pt.Count, 1, 0) OVER (PARTITION BY pt.TagName ORDER BY pt.LastActivityDate) as PrevCount,
        (pt.Count - LAG(pt.Count, 1, 0) OVER (PARTITION BY pt.TagName ORDER BY pt.LastActivityDate)) as CountChange
    FROM (
        SELECT 
            t.TagName,
            t.Count,
            MAX(p.LastActivityDate) as LastActivityDate,
            p.Id
        FROM Tags t
        JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
        WHERE p.CreationDate >= '2020-01-01'::timestamp
        GROUP BY t.TagName, t.Count, p.Id
    ) pt
),
PostsWithBadges AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        EXISTS(
            SELECT 1 
            FROM Badges b 
            WHERE b.UserId = p.OwnerUserId 
            AND b.Date >= p.CreationDate 
            AND b.Date <= p.LastActivityDate + INTERVAL '7 days'
        ) as UserHasRecentBadge,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = p.OwnerUserId
            AND b.Date BETWEEN p.CreationDate AND p.LastActivityDate
        ) as BadgeCount,
        (
            SELECT STRING_AGG(b.Name, ', ')
            FROM Badges b
            WHERE b.UserId = p.OwnerUserId
            AND b.Date BETWEEN p.CreationDate AND p.LastActivityDate
        ) as BadgeList
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
)
SELECT
    rp.Id as PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.ScoreCategory,
    rp.UserPostSequence,
    CASE 
        WHEN rp.PrevScore > 0 THEN 
            ROUND((rp.Score::numeric - rp.PrevScore::numeric) / rp.PrevScore::numeric * 100, 2)
        ELSE NULL 
    END as ScoreChangePercent,
    rp.AvgUserScore,
    rp.CleanTags,
    rp.TagCount,
    rp.HasRelatedPost,
    rp.DaysSinceLastActivity,
    us.ReputationTier,
    us.TotalPosts,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgScore as UserAvgScore,
    us.MaxScore as UserMaxScore,
    us.NetVotes,
    tt.PopularityRank,
    tt.TagCategory,
    ta.RecentActivity,
    ta.CountChange,
    psb.UserHasRecentBadge,
    psb.BadgeCount,
    psb.BadgeList,
    CASE 
        WHEN rp.Score > us.AvgScore AND us.ReputationTier IN ('Elite', 'Advanced')
        THEN 'High Performing'
        WHEN rp.Score < 0 
        THEN 'Low Performing'
        ELSE 'Regular'
    END as PerformanceCategory,
    (rp.Score * 0.3 + rp.ViewCount * 0.2 + 
     COALESCE(rp.CommentCount, 0) * 0.1 + 
     COALESCE(rp.AnswerCount, 0) * 0.15 + 
     COALESCE(rp.FavoriteCount, 0) * 0.25) as WeightedScore
FROM RankedPosts rp
LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
LEFT JOIN TopTags tt ON rp.Tags IS NOT NULL 
    AND rp.Tags != ''
    AND tt.TagName IN (
        SELECT TRIM(UNNEST(string_to_array(trim(rp.Tags, '<>'), '><')))
        WHERE TRIM(UNNEST(string_to_array(trim(rp.Tags, '<>'), '><'))) LIKE tt.TagName
    )
LEFT JOIN TagActivity ta ON tt.TagName = (
    SELECT TRIM(UNNEST(string_to_array(trim(rp.Tags, '<>'), '><')))
    WHERE TRIM(UNNEST(string_to_array(trim(rp.Tags, '<>'), '><'))) LIKE tt.TagName
    LIMIT 1
)
LEFT JOIN PostsWithBadges psb ON rp.Id = psb.Id
WHERE rp.ScoreRank <= 100
    AND us.TotalPosts >= 5
    AND (tt.PopularityRank <= 50 OR tt.PopularityRank IS NULL)
    AND rp.DaysSinceLastActivity < 365
    AND (
        rp.Score > 50
        OR (
            rp.AnswerCount > 0 
            OR COALESCE(rp.CommentCount, 0) > 3
        )
    )
ORDER BY 
    rp.Score DESC,
    psb.BadgeCount DESC,
    us.Reputation DESC,
    tt.PopularityRank ASC,
    rp.DaysSinceLastActivity ASC
LIMIT 1000;