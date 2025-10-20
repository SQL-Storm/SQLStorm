-- {"query": "29006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1525} 
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
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        NTILE(10) OVER (ORDER BY p.Score) as score_decile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(string_to_array(trim(p.Tags, '<>'), '><'), 1)
            ELSE 0 
        END as tag_count,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as engagement_metric
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN COUNT(p.Id) > 0 THEN 
                EXTRACT(DAY FROM MAX(p.CreationDate) - MIN(p.CreationDate)) 
            ELSE 0 
        END as DaysActive,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.ParentId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.LastActivityDate,
        rp.tag_count,
        rp.engagement_metric,
        rp.rn,
        rp.prev_score,
        rp.score_decile,
        CASE 
            WHEN rp.Score > 100 THEN 'High'
            WHEN rp.Score > 50 THEN 'Medium'
            WHEN rp.Score > 0 THEN 'Low'
            ELSE 'None'
        END as ScoreCategory,
        CASE 
            WHEN rp.engagement_metric > 1000 THEN 'Very Engaging'
            WHEN rp.engagement_metric > 500 THEN 'Engaging'
            WHEN rp.engagement_metric > 100 THEN 'Somewhat Engaging'
            ELSE 'Low Engagement'
        END as EngagementLevel,
        DATEDIFF('day', rp.CreationDate, rp.LastActivityDate) as DaysSinceLastActivity,
        CASE 
            WHEN rp.ParentId IS NOT NULL THEN 'Answer'
            WHEN rp.PostTypeId = 1 THEN 'Question'
            ELSE 'Other'
        END as PostCategory
    FROM RankedPosts rp
    WHERE rp.rn <= 5 -- Top 5 posts per user
)
SELECT 
    pa.Id,
    pa.PostTypeId,
    pa.OwnerUserId,
    us.DisplayName,
    pa.Score,
    pa.ViewCount,
    pa.CreationDate,
    pa.Title,
    pa.AnswerCount,
    pa.CommentCount,
    pa.FavoriteCount,
    pa.LastActivityDate,
    pa.tag_count,
    pa.engagement_metric,
    pa.ScoreCategory,
    pa.EngagementLevel,
    pa.DaysSinceLastActivity,
    pa.PostCategory,
    CASE 
        WHEN pa.Score < COALESCE(pa.prev_score, 0) THEN 'Dropped'
        WHEN pa.Score > COALESCE(pa.prev_score, 0) THEN 'Improved'
        WHEN pa.Score = COALESCE(pa.prev_score, 0) THEN 'Maintained'
        ELSE 'New'
    END as PerformanceTrend,
    CASE 
        WHEN pa.score_decile <= 2 THEN 'Top 20%'
        WHEN pa.score_decile <= 5 THEN 'Top 50%'
        WHEN pa.score_decile <= 8 THEN 'Top 80%'
        ELSE 'Lower Percentile'
    END as ScorePercentile,
    ROW_NUMBER() OVER (ORDER BY pa.engagement_metric DESC) as EngagementRank,
    FIRST_VALUE(pa.Title) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate DESC) as LatestPostTitle,
    LAG(pa.Score, 1) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) as PrevScore,
    AVG(pa.Score) OVER (PARTITION BY pa.OwnerUserId) as AvgScorePerUser,
    STRING_AGG(pv.VoteType, ', ') as VoteSummary,
    CASE 
        WHEN COUNT(pv.Id) > 0 THEN 'Has Votes'
        ELSE 'No Votes'
    END as VotingStatus,
    CASE 
        WHEN pa.AnswerCount > 0 THEN 
            (pa.AnswerCount * 100.0 / NULLIF(pa.AnswerCount + pa.CommentCount, 0))::numeric(5,2)
        ELSE 0
    END as AnswerRatio,
    COALESCE(ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate DESC), 0) as UserPostRank
FROM PostAnalysis pa
INNER JOIN UserStats us ON pa.OwnerUserId = us.UserId
LEFT JOIN (
    SELECT 
        v.PostId,
        vt.Name as VoteType,
        COUNT(*) as VoteCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.VoteTypeId IN (2, 3) -- Upvotes and Downvotes
    GROUP BY v.PostId, vt.Name
) pv ON pa.Id = pv.PostId
WHERE pa.CreationDate >= '2020-01-01'::timestamp
GROUP BY 
    pa.Id, pa.PostTypeId, pa.OwnerUserId, us.DisplayName, pa.Score, pa.ViewCount, 
    pa.CreationDate, pa.Title, pa.AnswerCount, pa.CommentCount, pa.FavoriteCount, 
    pa.LastActivityDate, pa.tag_count, pa.engagement_metric, pa.ScoreCategory, 
    pa.EngagementLevel, pa.DaysSinceLastActivity, pa.PostCategory, pa.prev_score,
    pa.score_decile, pa.rn
HAVING 
    pa.engagement_metric > 100
    AND (pa.Score > 0 OR pa.ViewCount > 0)
ORDER BY pa.engagement_metric DESC, pa.CreationDate DESC
LIMIT 1000;