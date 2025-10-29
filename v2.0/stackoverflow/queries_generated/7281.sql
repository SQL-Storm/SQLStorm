-- {"query": "7281.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1608} 
WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, 0 as Level
    FROM Tags t
    WHERE t.IsRequired = 1
    UNION ALL
    SELECT t.Id, t.TagName, t.Count, rth.Level + 1
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy rth ON t.Id = rth.Id
    WHERE rth.Level < 3
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END as UserTier,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.Score > 10 THEN 'Highly Rated'
            ELSE 'Normal'
        END as PostStatus,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        COUNT(*) OVER () as TotalPosts,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) as NextScore
    FROM Posts p
),
ComplexTagAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.Tags,
        COALESCE(STRING_AGG(t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL), 'No Tags') as TagList,
        STRING_TO_ARRAY(COALESCE(pa.Tags, ''), '><') as TagArray,
        (SELECT COUNT(*) FROM UNNEST(STRING_TO_ARRAY(COALESCE(pa.Tags, ''), '><')) AS tag WHERE tag != '') as TagCount,
        CASE 
            WHEN EXISTS (SELECT 1 FROM UNNEST(STRING_TO_ARRAY(COALESCE(pa.Tags, ''), '><')) AS tag WHERE tag LIKE '%sql%') THEN 'SQL Related'
            ELSE 'Other'
        END as TechCategory,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as UserPostRank
    FROM PostAnalysis pa
    LEFT JOIN LATERAL (
        SELECT t.TagName
        FROM Tags t
        WHERE t.TagName IN (
            SELECT UNNEST(STRING_TO_ARRAY(COALESCE(pa.Tags, ''), '><'))
            WHERE UNNEST(STRING_TO_ARRAY(COALESCE(pa.Tags, ''), '><')) != ''
        )
    ) t ON TRUE
    GROUP BY pa.PostId, pa.Title, pa.Score, pa.Tags, pa.OwnerUserId
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserTier,
    uas.ReputationRank,
    uas.PostCount,
    uas.CommentCount,
    uas.BadgeCount,
    uas.AvgPostScore,
    uas.LastPostDate,
    STRING_AGG(cta.Title, '; ') FILTER (WHERE cta.Score > 5) as HighScoredPosts,
    STRING_AGG(cta.TagList, '; ') as AllTags,
    COUNT(*) FILTER (WHERE cta.TechCategory = 'SQL Related') as SqlRelatedPosts,
    COUNT(*) FILTER (WHERE cta.ScoreRank <= 10) as Top10ScoredPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.CreationDate >= '2022-01-01') as RecentPosts,
    COALESCE(
        (SELECT STRING_AGG(CONCAT('Badge: ', b.Name, ' (', b.Date, ')'), ', ') 
         FROM Badges b 
         WHERE b.UserId = uas.UserId 
         AND b.Date >= '2022-01-01' 
         ORDER BY b.Date DESC 
         LIMIT 5), 
        'No recent badges'
    ) as RecentBadges,
    CASE 
        WHEN uas.PostCount > 50 AND uas.BadgeCount > 10 THEN 'Active Contributor'
        WHEN uas.PostCount > 20 THEN 'Regular Poster'
        WHEN uas.PostCount > 5 THEN 'Occasional Poster'
        ELSE 'New User'
    END as ActivityLevel,
    (SELECT COUNT(DISTINCT ph.PostId) 
     FROM PostHistory ph 
     WHERE ph.UserId = uas.UserId 
     AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditActivity,
    COALESCE(
        (SELECT AVG(p.Score) 
         FROM Posts p 
         WHERE p.OwnerUserId = uas.UserId 
         AND p.PostTypeId = 1), 
        0
    ) as AvgQuestionScore,
    COALESCE(
        (SELECT AVG(p.Score) 
         FROM Posts p 
         WHERE p.OwnerUserId = uas.UserId 
         AND p.PostTypeId = 2), 
        0
    ) as AvgAnswerScore
FROM UserActivityStats uas
LEFT JOIN ComplexTagAnalysis cta ON uas.UserId = cta.OwnerUserId
WHERE 
    uas.Reputation > 100
    AND uas.PostCount > 1
    AND (
        cta.Tags IS NOT NULL 
        OR EXISTS (
            SELECT 1 FROM Posts p 
            WHERE p.OwnerUserId = uas.UserId 
            AND p.PostTypeId IN (1, 2)
        )
    )
GROUP BY 
    uas.UserId, 
    uas.DisplayName, 
    uas.Reputation, 
    uas.UserTier, 
    uas.ReputationRank, 
    uas.PostCount, 
    uas.CommentCount, 
    uas.BadgeCount, 
    uas.AvgPostScore, 
    uas.LastPostDate
HAVING 
    COUNT(cta.PostId) > 0
ORDER BY 
    uas.Reputation DESC,
    uas.PostCount DESC
LIMIT 50;