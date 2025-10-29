-- {"query": "7032.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1989} 
WITH RECURSIVE QuestionHierarchy AS (
    SELECT 
        p.Id as QuestionId,
        p.ParentId as AnswerId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        0 as Level,
        CAST(p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL
    
    UNION ALL
    
    SELECT 
        qh.QuestionId,
        p.Id as AnswerId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        qh.Level + 1,
        CAST(qh.Path || '->' || p.Id AS VARCHAR(1000))
    FROM Posts p
    INNER JOIN QuestionHierarchy qh ON p.ParentId = qh.AnswerId
    WHERE qh.Level < 3
),
TagStatistics AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.ViewCount, 0) as WikiViews,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            ELSE 'Standard'
        END as TagType
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(v.CreationDate) as LastVoteDate,
        MAX(c.CreationDate) as LastCommentDate,
        CASE 
            WHEN u.Views > 10000 THEN 'Elite'
            WHEN u.Views > 5000 THEN 'Veteran'
            WHEN u.Views > 1000 THEN 'Experienced'
            ELSE 'Regular'
        END as UserTier
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
AnswerQuality AS (
    SELECT 
        pa.Id as AnswerId,
        pa.ParentId as QuestionId,
        pa.Score as AnswerScore,
        pa.CreationDate as AnswerDate,
        pa.OwnerUserId as AnswerOwner,
        q.Score as QuestionScore,
        q.Title as QuestionTitle,
        q.CreationDate as QuestionDate,
        COALESCE(pa.Score - LAG(pa.Score) OVER (PARTITION BY pa.ParentId ORDER BY pa.CreationDate), 0) as ScoreChange,
        CASE 
            WHEN pa.Score >= 10 THEN 'High Quality'
            WHEN pa.Score >= 5 THEN 'Medium Quality'
            WHEN pa.Score >= 1 THEN 'Low Quality'
            ELSE 'Poor Quality'
        END as QualityLevel
    FROM PostAnalysis pa
    INNER JOIN PostAnalysis q ON pa.ParentId = q.Id
    WHERE pa.PostTypeId = 2
),
FinalAggregation AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Views as UserViews,
        ua.CommentCount,
        ua.VoteCount,
        ua.BadgeCount,
        ua.UserTier,
        COUNT(DISTINCT CASE WHEN pa.PostTypeId = 1 THEN pa.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN pa.PostTypeId = 2 THEN pa.Id END) as AnswerCount,
        SUM(CASE WHEN pa.PostTypeId = 1 THEN pa.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN pa.PostTypeId = 2 THEN pa.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN pa.PostTypeId = 1 THEN pa.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN pa.PostTypeId = 2 THEN pa.Score ELSE NULL END) as AvgAnswerScore,
        MAX(pa.CreationDate) as LatestPostDate,
        MAX(pa.Score) as MaxPostScore,
        MIN(pa.Score) as MinPostScore,
        COUNT(DISTINCT CASE 
            WHEN pa.PostTypeId = 1 AND pa.Score > 100 THEN pa.Id 
            WHEN pa.PostTypeId = 2 AND pa.Score > 50 THEN pa.Id 
        END) as HighImpactPostCount
    FROM UserActivity ua
    INNER JOIN PostAnalysis pa ON ua.UserId = pa.OwnerUserId
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.Views, ua.CommentCount, ua.VoteCount, ua.BadgeCount, ua.UserTier
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.UserViews,
    fa.CommentCount,
    fa.VoteCount,
    fa.BadgeCount,
    fa.UserTier,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.TotalQuestionScore,
    fa.TotalAnswerScore,
    fa.AvgQuestionScore,
    fa.AvgAnswerScore,
    fa.LatestPostDate,
    fa.MaxPostScore,
    fa.MinPostScore,
    fa.HighImpactPostCount,
    CASE 
        WHEN fa.VoteCount > 0 THEN (fa.BadgeCount * 100.0) / fa.VoteCount
        ELSE 0
    END as BadgeEfficiency,
    CASE 
        WHEN fa.QuestionCount > 0 AND fa.AnswerCount > 0 THEN 
            (CAST(fa.TotalAnswerScore AS FLOAT) * 100.0) / (CAST(fa.TotalQuestionScore AS FLOAT))
        ELSE 0
    END as AnswerQualityRatio,
    CASE 
        WHEN fa.Reputation > 10000 THEN 'Expert Level'
        WHEN fa.Reputation > 5000 THEN 'Advanced Level'
        WHEN fa.Reputation > 1000 THEN 'Intermediate Level'
        ELSE 'Beginner Level'
    END as ReputationTier,
    STRING_AGG(
        CASE WHEN pa.PostTypeId = 1 THEN pa.Title || ' (' || pa.Score || ')' END, 
        '; ' ORDER BY pa.CreationDate DESC
    ) as RecentQuestions,
    STRING_AGG(
        CASE WHEN pa.PostTypeId = 2 THEN pa.Title || ' (' || pa.Score || ')' END, 
        '; ' ORDER BY pa.CreationDate DESC
    ) as RecentAnswers,
    STDEV(pa.Score) as ScoreDeviation,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pa.Score) as MedianScore,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.Score >= 100) as HighScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.Score < 0) as NegativeScorePosts,
    DATEDIFF(day, MIN(pa.CreationDate), MAX(pa.CreationDate)) as PostingDurationDays
FROM FinalAggregation fa
LEFT JOIN PostAnalysis pa ON fa.UserId = pa.OwnerUserId
GROUP BY 
    fa.UserId, fa.DisplayName, fa.Reputation, fa.UserViews, fa.CommentCount, 
    fa.VoteCount, fa.BadgeCount, fa.UserTier, fa.QuestionCount, fa.AnswerCount,
    fa.TotalQuestionScore, fa.TotalAnswerScore, fa.AvgQuestionScore, fa.AvgAnswerScore,
    fa.LatestPostDate, fa.MaxPostScore, fa.MinPostScore, fa.HighImpactPostCount
HAVING 
    COUNT(pa.Id) > 0 
    AND (COUNT(DISTINCT CASE WHEN pa.PostTypeId = 1 THEN pa.Id END) > 0 
         OR COUNT(DISTINCT CASE WHEN pa.PostTypeId = 2 THEN pa.Id END) > 0)
ORDER BY 
    fa.Reputation DESC, fa.UserViews DESC, fa.QuestionCount DESC
LIMIT 1000;