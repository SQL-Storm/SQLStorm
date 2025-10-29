-- {"query": "7207.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1769} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) as rn
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' 
      AND u.CreationDate <= '2023-12-31'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        TotalScore,
        CommentCount,
        BadgeCount,
        LastPostDate,
        CASE 
            WHEN PostCount > 1000 THEN 'Elite'
            WHEN PostCount > 500 THEN 'Veteran'
            WHEN PostCount > 100 THEN 'Contributor'
            WHEN PostCount > 0 THEN 'Active'
            ELSE 'Inactive'
        END as UserTier,
        DENSE_RANK() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        NTILE(100) OVER (ORDER BY Reputation DESC) as ReputationPercentile
    FROM UserActivityStats
    WHERE rn = 1
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        p.Tags,
        COALESCE(p.Tags, '') as TagString,
        LENGTH(COALESCE(p.Tags, '')) as TagLength,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score > 0) as PositiveAnswers,
        (SELECT AVG(Score) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as AvgAnswerScore,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END as HasAcceptedAnswer,
        CASE 
            WHEN p.CommentCount > 10 THEN 'High Comment Activity'
            WHEN p.CommentCount > 5 THEN 'Medium Comment Activity'
            ELSE 'Low Comment Activity'
        END as CommentActivityLevel,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' 
      AND p.CreationDate <= '2023-12-31'
      AND p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        COALESCE(t.ExcerptPostId, 0) as ExcerptPostId,
        COALESCE(t.WikiPostId, 0) as WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity,
        NTH_VALUE(t.TagName, 10) OVER (ORDER BY t.Count DESC) as Top10Tag
    FROM Tags t
    WHERE t.Count > 0
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.TotalScore,
    tu.CommentCount,
    tu.BadgeCount,
    tu.LastPostDate,
    tu.UserTier,
    tu.ScoreRank,
    tu.ReputationPercentile,
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.AnswerCount,
    pa.CommentCount,
    pa.CreationDate,
    pa.PostType,
    pa.TagString,
    pa.TagLength,
    pa.PositiveAnswers,
    pa.AvgAnswerScore,
    pa.HasAcceptedAnswer,
    pa.CommentActivityLevel,
    pa.PrevScore,
    pa.NextScore,
    ta.TagName,
    ta.Count as TagCount,
    ta.ExcerptPostId,
    ta.WikiPostId,
    ta.TagPopularity,
    ta.RankByPopularity,
    ta.Top10Tag,
    CASE 
        WHEN tu.PostCount > 100 AND tu.Reputation > 10000 THEN 'Highly Engaged'
        WHEN tu.PostCount > 50 AND tu.Reputation > 5000 THEN 'Engaged'
        WHEN tu.PostCount > 10 AND tu.Reputation > 1000 THEN 'Active'
        ELSE 'Regular'
    END as EngagementLevel,
    CASE 
        WHEN pa.Score > 100 AND pa.ViewCount > 1000 THEN 'Viral Content'
        WHEN pa.Score > 50 AND pa.ViewCount > 500 THEN 'Popular Content'
        WHEN pa.Score > 10 AND pa.ViewCount > 100 THEN 'Notable Content'
        ELSE 'Standard Content'
    END as ContentImpact,
    COALESCE(100.0 * pa.Score / NULLIF(pa.ViewCount, 0), 0) as ScoreToViewRatio,
    COALESCE(100.0 * pa.CommentCount / NULLIF(pa.AnswerCount, 0), 0) as CommentToAnswerRatio,
    CASE 
        WHEN pa.PositiveAnswers > 2 THEN 'High Answer Quality'
        WHEN pa.PositiveAnswers > 0 THEN 'Moderate Answer Quality'
        ELSE 'Low Answer Quality'
    END as AnswerQuality,
    IIF(tu.ScoreRank <= 100, 'Top 100', 'Other') as TopRankIndicator,
    IIF(pa.HasAcceptedAnswer = 1, 'Answered', 'Unanswered') as QuestionStatus,
    CASE 
        WHEN pa.Score >= 500 THEN 'Controversial'
        WHEN pa.Score > 100 THEN 'Interesting'
        WHEN pa.Score > 0 THEN 'Moderate'
        ELSE 'Low Interest'
    END as TopicInterestLevel,
    ABS(pa.Score - COALESCE(pa.PrevScore, 0)) as ScoreChangeSinceLast,
    DATEDIFF(day, pa.CreationDate, GETDATE()) as DaysSinceCreation,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = pa.PostId AND p2.PostTypeId = 2) as TotalAnswers,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 2) as Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 3) as Downvotes,
    (SELECT TOP 1 v.CreationDate FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 2 ORDER BY v.CreationDate DESC) as LastUpvoteDate
FROM TopUsers tu
FULL OUTER JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
LEFT JOIN TagAnalysis ta ON CHARINDEX(ta.TagName, pa.TagString) > 0
WHERE tu.UserId IS NOT NULL OR pa.PostId IS NOT NULL
  AND (tu.UserId IS NULL OR tu.Reputation > 1000)
  AND (pa.PostId IS NULL OR pa.Score > -10)
ORDER BY 
    tu.ScoreRank,
    pa.CreationDate DESC,
    pa.Score DESC,
    pa.ViewCount DESC
OPTION (MAXDOP 8)