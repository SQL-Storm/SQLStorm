-- {"query": "7534.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1428} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as avg_score_5period
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answer_count,
        MAX(p.CreationDate) as last_post_date,
        STUFF((
            SELECT DISTINCT ',' + t.TagName
            FROM Posts p2
            JOIN Tags t ON p2.Tags LIKE '%' + t.TagName + '%' 
            WHERE p2.OwnerUserId = u.Id
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') as user_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE Tags LIKE '%' + t.TagName + '%'), 0) as post_count,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as last_used_date
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
ComplexAnalysis AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.Tags,
        rp.OwnerUserId,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.prev_score,
        rp.next_score,
        rp.avg_score_5period,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        CASE 
            WHEN rp.Score > rp.prev_score AND rp.Score > rp.next_score THEN 'Peak'
            WHEN rp.Score < rp.prev_score AND rp.Score < rp.next_score THEN 'Valley'
            ELSE 'Normal'
        END as trend,
        COALESCE(ua.user_tags, 'No tags') as associated_tags,
        (SELECT COUNT(*) FROM Posts p WHERE p.ParentId = rp.Id AND p.PostTypeId = 2) as answer_count,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) as comment_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId IN (2,3)) as vote_count,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.5 THEN 'Elite'
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.2 THEN 'Above Average'
            ELSE 'Average'
        END as performance_level,
        ABS(rp.Score - COALESCE(rp.prev_score, 0)) as score_change
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.rn <= 5
)
SELECT 
    ca.Id,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.Tags,
    ca.OwnerUserId,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.prev_score,
    ca.next_score,
    ca.avg_score_5period,
    ca.score_category,
    ca.trend,
    ca.associated_tags,
    ca.vote_count,
    ca.performance_level,
    ca.score_change,
    DENSE_RANK() OVER (ORDER BY ca.Score DESC) as rank_by_score,
    PERCENT_RANK() OVER (ORDER BY ca.Score) as percentile_rank,
    NTILE(4) OVER (ORDER BY ca.Score) as quartile,
    CASE 
        WHEN ca.Score >= 100 THEN 'Hot'
        WHEN ca.Score >= 50 THEN 'Warm'
        WHEN ca.Score >= 10 THEN 'Cool'
        ELSE 'Cold'
    END as热度等级,
    COALESCE(CAST(ca.score_change AS VARCHAR(10)), 'N/A') as score_change_str,
    CAST(ca.Score AS VARCHAR(20)) + ' - ' + CAST(ca.ViewCount AS VARCHAR(20)) + ' views' as score_view_display,
    CASE 
        WHEN ca.Tags IS NOT NULL AND LEN(ca.Tags) > 0 THEN 
            SUBSTRING(ca.Tags, 2, LEN(ca.Tags) - 2)
        ELSE 'No tags'
    END as clean_tags
FROM ComplexAnalysis ca
WHERE ca.OwnerUserId IN (
    SELECT UserId 
    FROM UserActivity 
    WHERE post_count > 50 AND reputation > 10000
)
AND EXISTS (
    SELECT 1 
    FROM TagStats ts 
    WHERE ts.TagName IN (
        SELECT value 
        FROM STRING_SPLIT(TRIM(BOTH '<>' FROM ca.Tags), '><')
    )
    AND (ts.post_count > 50 OR ts.Count > 100)
)
ORDER BY ca.Score DESC, ca.ViewCount DESC, ca.CreationDate DESC
OPTION (MAXDOP 4, RECOMPILE);