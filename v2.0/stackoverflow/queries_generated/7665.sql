-- {"query": "7665.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1509} 
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_date
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastActivity,
        STRING_AGG(DISTINCT p.Tags, '; ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as PrevCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
ComplexFilter AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.ParentId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn,
        rp.prev_score,
        rp.prev_date,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.prev_date IS NOT NULL 
            THEN DATEDIFF('DAY', rp.prev_date, rp.CreationDate)
            ELSE NULL 
        END as DaysSinceLastPost,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.prev_score < rp.Score 
            THEN 'Improved'
            WHEN rp.prev_score IS NOT NULL AND rp.prev_score > rp.Score 
            THEN 'Declined'
            ELSE 'Same'
        END as ScoreChange
    FROM RankedPosts rp
    WHERE rp.Score > 0 AND rp.OwnerUserId IS NOT NULL
)
SELECT 
    COALESCE(us.DisplayName, 'Anonymous') as DisplayName,
    us.Reputation,
    us.PostCount,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgScore,
    us.LastActivity,
    COALESCE(LEFT(us.AllTags, 200), 'No tags') as TagSummary,
    COUNT(DISTINCT cf.Id) as FilteredPosts,
    SUM(CASE WHEN cf.PostTypeId = 1 THEN 1 ELSE 0 END) as FilteredQuestions,
    SUM(CASE WHEN cf.PostTypeId = 2 THEN 1 ELSE 0 END) as FilteredAnswers,
    AVG(cf.Score) as AvgFilteredScore,
    MIN(cf.CreationDate) as FirstFilteredPost,
    MAX(cf.CreationDate) as LatestFilteredPost,
    STRING_AGG(DISTINCT ta.TagName, ', ') as RelatedTags,
    STRING_AGG(DISTINCT cf.Title, ' | ') as PostTitles,
    COALESCE(COUNT(DISTINCT bl.Id), 0) as BountyCount,
    COALESCE(COUNT(DISTINCT pv.Id), 0) as UpVoteCount,
    COALESCE(COUNT(DISTINCT cd.Id), 0) as DownVoteCount,
    COALESCE(SUM(CASE WHEN cf.Score > 0 THEN 1 ELSE 0 END), 0) as PositiveScorePosts,
    COALESCE(SUM(CASE WHEN cf.Score < 0 THEN 1 ELSE 0 END), 0) as NegativeScorePosts,
    COALESCE(SUM(CASE WHEN cf.Score = 0 THEN 1 ELSE 0 END), 0) as NeutralScorePosts,
    COALESCE(STRING_AGG(DISTINCT CASE WHEN cf.Score > 0 THEN cf.Score::VARCHAR ELSE NULL END, ', '), '') as PositiveScores,
    COALESCE(STRING_AGG(DISTINCT CASE WHEN cf.Score < 0 THEN cf.Score::VARCHAR ELSE NULL END, ', '), '') as NegativeScores,
    COUNT(DISTINCT CASE WHEN cf.Score > 10 THEN cf.Id ELSE NULL END) as HighScoringPosts,
    COUNT(DISTINCT CASE WHEN cf.Score <= 10 AND cf.Score > 0 THEN cf.Id ELSE NULL END) as MediumScoringPosts,
    COUNT(DISTINCT CASE WHEN cf.Score <= 0 THEN cf.Id ELSE NULL END) as LowScoringPosts,
    AVG(CASE WHEN cf.DaysSinceLastPost IS NOT NULL THEN cf.DaysSinceLastPost ELSE NULL END) as AvgDaysBetweenPosts,
    STRING_AGG(DISTINCT CASE WHEN cf.ScoreChange = 'Improved' THEN 'Improved' ELSE NULL END, ', ') as ImprovementIndicators
FROM UserStats us
LEFT JOIN ComplexFilter cf ON us.UserId = cf.OwnerUserId
LEFT JOIN TagAnalysis ta ON EXISTS (
    SELECT 1 FROM STRING_TO_ARRAY(COALESCE(cf.Tags, ''), '>') s 
    WHERE s LIKE '%' || COALESCE(ta.TagName, '') || '%'
)
LEFT JOIN PostLinks bl ON cf.Id = bl.PostId AND bl.LinkTypeId = 8
LEFT JOIN Votes pv ON cf.Id = pv.PostId AND pv.VoteTypeId = 2
LEFT JOIN Votes cd ON cf.Id = cd.PostId AND cd.VoteTypeId = 3
WHERE us.UserId IS NOT NULL
    AND (cf.PostTypeId = 1 OR cf.PostTypeId = 2 OR cf.PostTypeId IS NULL)
    AND (cf.Score > 0 OR cf.Score IS NULL) 
    AND us.PostCount > 0
GROUP BY 
    us.UserId, us.DisplayName, us.Reputation, us.PostCount, 
    us.QuestionCount, us.AnswerCount, us.AvgScore, us.LastActivity, 
    us.AllTags
HAVING 
    COUNT(DISTINCT cf.Id) > 0
    AND COUNT(DISTINCT CASE WHEN cf.Score > 0 THEN cf.Id ELSE NULL END) > 0
ORDER BY 
    us.Reputation DESC,
    us.LastActivity DESC,
    COUNT(DISTINCT cf.Id) DESC
LIMIT 100;