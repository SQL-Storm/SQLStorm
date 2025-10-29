-- {"query": "7209.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2057} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(10) OVER (ORDER BY p.Score) as ScoreDecile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgScore,
        MAX(p.CreationDate) as LastActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderately Popular'
            ELSE 'Less Popular'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
PostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.UserPostRank,
        rp.PrevScore,
        rp.ScoreRank,
        rp.ScoreDecile,
        CASE 
            WHEN rp.Score > 100 THEN 'Highly Voted'
            WHEN rp.Score > 50 THEN 'Moderately Voted'
            WHEN rp.Score > 0 THEN 'Low Voted'
            ELSE 'No Votes'
        END as VotingCategory,
        CASE 
            WHEN rp.UserPostRank = 1 THEN 'Most Recent'
            WHEN rp.UserPostRank <= 3 THEN 'Recent'
            ELSE 'Older'
        END as RecencyCategory,
        CASE 
            WHEN rp.Score > 0 THEN rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)
            ELSE 0
        END as EngagementRatio
    FROM RankedPosts rp
),
FilteredPosts AS (
    SELECT 
        pa.Id,
        pa.PostTypeId,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.Title,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.UserPostRank,
        pa.PrevScore,
        pa.ScoreRank,
        pa.ScoreDecile,
        pa.VotingCategory,
        pa.RecencyCategory,
        pa.EngagementRatio,
        CAST(pa.CreationDate AS DATE) as PostDate,
        EXTRACT(YEAR FROM pa.CreationDate) as PostYear,
        EXTRACT(MONTH FROM pa.CreationDate) as PostMonth,
        EXTRACT(DAY FROM pa.CreationDate) as PostDay,
        CASE 
            WHEN pa.Tags LIKE '%<c>%' OR pa.Tags LIKE '%<java>%' THEN 'Programming'
            WHEN pa.Tags LIKE '%<sql>%' OR pa.Tags LIKE '%<database>%' THEN 'Database'
            WHEN pa.Tags LIKE '%<python>%' OR pa.Tags LIKE '%<machine-learning>%' THEN 'Data Science'
            ELSE 'Other'
        END as SubjectCategory
    FROM PostAnalysis pa
    WHERE pa.Score > 0 
      AND pa.ViewCount > 10
      AND pa.CreationDate >= '2020-01-01 00:00:00'
      AND pa.CreationDate <= '2023-12-31 23:59:59'
),
TaggedPosts AS (
    SELECT 
        fp.Id,
        fp.PostTypeId,
        fp.Score,
        fp.ViewCount,
        fp.CreationDate,
        fp.OwnerUserId,
        fp.Title,
        fp.Tags,
        fp.AnswerCount,
        fp.CommentCount,
        fp.FavoriteCount,
        fp.UserPostRank,
        fp.PrevScore,
        fp.ScoreRank,
        fp.ScoreDecile,
        fp.VotingCategory,
        fp.RecencyCategory,
        fp.EngagementRatio,
        fp.PostDate,
        fp.PostYear,
        fp.PostMonth,
        fp.PostDay,
        fp.SubjectCategory,
        CASE 
            WHEN fp.Tags IS NOT NULL AND fp.Tags != '' THEN 
                STRING_AGG(SUBSTRING(fp.Tags, POSITION('<' IN fp.Tags) + 1, POSITION('>' IN fp.Tags) - POSITION('<' IN fp.Tags) - 1), ', ')
            ELSE 'No Tags'
        END as ExtractedTags,
        ARRAY_POSITION(STRING_TO_ARRAY(fp.Tags, '><'), 'c') as CTagPosition,
        ARRAY_POSITION(STRING_TO_ARRAY(fp.Tags, '><'), 'python') as PythonTagPosition
    FROM FilteredPosts fp
    GROUP BY 
        fp.Id, fp.PostTypeId, fp.Score, fp.ViewCount, fp.CreationDate, fp.OwnerUserId, 
        fp.Title, fp.Tags, fp.AnswerCount, fp.CommentCount, fp.FavoriteCount, 
        fp.UserPostRank, fp.PrevScore, fp.ScoreRank, fp.ScoreDecile, 
        fp.VotingCategory, fp.RecencyCategory, fp.EngagementRatio, 
        fp.PostDate, fp.PostYear, fp.PostMonth, fp.PostDay, fp.SubjectCategory
)
SELECT 
    tp.Id,
    tp.PostTypeId,
    tp.Score,
    tp.ViewCount,
    tp.CreationDate,
    tp.OwnerUserId,
    tp.Title,
    tp.Tags,
    tp.AnswerCount,
    tp.CommentCount,
    tp.FavoriteCount,
    tp.UserPostRank,
    tp.PrevScore,
    tp.ScoreRank,
    tp.ScoreDecile,
    tp.VotingCategory,
    tp.RecencyCategory,
    tp.EngagementRatio,
    tp.PostDate,
    tp.PostYear,
    tp.PostMonth,
    tp.PostDay,
    tp.SubjectCategory,
    tp.ExtractedTags,
    tp.CTagPosition,
    tp.PythonTagPosition,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.TotalScore,
    ua.AvgScore,
    CASE 
        WHEN tp.Score > 100 AND tp.ViewCount > 1000 THEN 'High Impact'
        WHEN tp.Score > 50 AND tp.ViewCount > 500 THEN 'Medium Impact'
        WHEN tp.Score > 0 AND tp.ViewCount > 100 THEN 'Low Impact'
        ELSE 'No Impact'
    END as ImpactLevel,
    CASE 
        WHEN tp.Score > (SELECT AVG(Score) FROM FilteredPosts) THEN 'Above Average'
        WHEN tp.Score < (SELECT AVG(Score) FROM FilteredPosts) THEN 'Below Average'
        ELSE 'Average'
    END as PerformanceLevel,
    CASE 
        WHEN tp.Tags IS NULL OR tp.Tags = '' THEN 'No Tags'
        WHEN tp.SubjectCategory = 'Programming' THEN 'Programming Topic'
        WHEN tp.SubjectCategory = 'Database' THEN 'Database Topic'
        ELSE 'Other Topic'
    END as TopicCategory,
    ABS(tp.Score - COALESCE(tp.PrevScore, 0)) as ScoreChange,
    ROW_NUMBER() OVER (ORDER BY tp.EngagementRatio DESC) as EngagementRank,
    LAG(tp.Id, 1) OVER (ORDER BY tp.CreationDate) as PreviousPostId,
    LEAD(tp.Id, 1) OVER (ORDER BY tp.CreationDate) as NextPostId,
    CASE 
        WHEN tp.CTagPosition IS NOT NULL AND tp.CTagPosition > 0 THEN 'C Tag Present'
        WHEN tp.PythonTagPosition IS NOT NULL AND tp.PythonTagPosition > 0 THEN 'Python Tag Present'
        ELSE 'Other Tags'
    END as LanguageTagStatus,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tp.Id) as CommentCountActual,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.Id AND v.VoteTypeId = 2) as UpvoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.Id AND v.VoteTypeId = 3) as DownvoteCount
FROM TaggedPosts tp
LEFT JOIN UserActivityStats ua ON tp.OwnerUserId = ua.UserId
WHERE tp.PostYear BETWEEN 2020 AND 2023
  AND tp.PostMonth BETWEEN 1 AND 12
  AND (tp.CTagPosition IS NOT NULL OR tp.PythonTagPosition IS NOT NULL)
ORDER BY tp.CreationDate DESC, tp.Score DESC
LIMIT 1000 OFFSET 0;