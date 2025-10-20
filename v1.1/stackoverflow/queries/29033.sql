WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        NTILE(100) OVER (ORDER BY u.Reputation DESC) AS ReputationPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        LastPostDate,
        PostRank,
        ReputationPercentile,
        CASE 
            WHEN TotalPosts > 100 THEN 'Elite'
            WHEN TotalPosts > 50 THEN 'Veteran'
            WHEN TotalPosts > 10 THEN 'Regular'
            ELSE 'Newbie'
        END AS UserTier,
        CASE 
            WHEN Reputation >= 100000 THEN 'Legendary'
            WHEN Reputation >= 10000 THEN 'Master'
            WHEN Reputation >= 1000 THEN 'Expert'
            WHEN Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationTier
    FROM UserActivityStats
    WHERE PostRank <= 1000
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.LastActivityDate,
        p.LastEditDate,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Has Answers'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostStatus,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High Traffic'
            WHEN p.ViewCount > 100 THEN 'Medium Traffic'
            WHEN p.ViewCount > 10 THEN 'Low Traffic'
            ELSE 'Minimal Traffic'
        END AS TrafficLevel,
        CAST((EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400) AS INTEGER) AS DaysSinceLastActivity,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PostPopularityRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        CASE 
            WHEN LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) IS NOT NULL 
                 AND p.Score > LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) 
            THEN 'Improved'
            WHEN LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) IS NOT NULL 
                 AND p.Score < LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) 
            THEN 'Declined'
            ELSE 'Stable'
        END AS ScoreTrend
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
AnswerQuality AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.PostStatus,
        pa.PostPopularityRank,
        pa.ScorePercentile,
        pa.ScoreTrend,
        (SELECT AVG(Score) FROM Posts pa2 WHERE pa2.ParentId = pa.PostId AND pa2.PostTypeId = 2) AS AvgAnswerScore,
        (SELECT COUNT(*) FROM Posts pa3 WHERE pa3.ParentId = pa.PostId AND pa3.PostTypeId = 2 AND pa3.Score > 0) AS PositiveAnswers,
        (SELECT COUNT(*) FROM Posts pa4 WHERE pa4.ParentId = pa.PostId AND pa4.PostTypeId = 2 AND pa4.Score < 0) AS NegativeAnswers,
        (SELECT COUNT(DISTINCT UserId) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId IN (2, 3)) AS VoterCount,
        CASE 
            WHEN pa.Score > 100 AND pa.ViewCount > 1000 THEN 'High Impact'
            WHEN pa.Score > 50 AND pa.ViewCount > 500 THEN 'Moderate Impact'
            WHEN pa.Score > 10 AND pa.ViewCount > 100 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END AS ImpactLevel
    FROM PostAnalysis pa
    WHERE pa.PostTypeId = 1
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS PostsWithTag,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS AvgScoreForTag,
        (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS UniquePosters,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderately Popular'
            WHEN t.Count > 10 THEN 'Less Popular'
            ELSE 'Rare'
        END AS PopularityLevel
    FROM Tags t
    WHERE t.TagName IS NOT NULL
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.UserTier,
    tu.ReputationTier,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    tu.Comments,
    tu.Badges,
    tu.LastPostDate,
    tu.PostRank,
    tu.ReputationPercentile,
    pa.PostId,
    pa.Title AS PostTitle,
    pa.PostTypeId,
    pa.PostStatus,
    pa.Score,
    pa.ViewCount,
    pa.AnswerCount,
    pa.CommentCount,
    pa.TrafficLevel,
    pa.ScoreTrend,
    pa.DaysSinceLastActivity,
    pa.PostPopularityRank,
    pa.ScorePercentile,
    aq.AvgAnswerScore,
    aq.PositiveAnswers,
    aq.NegativeAnswers,
    aq.VoterCount,
    aq.ImpactLevel,
    ta.TagName,
    ta.PopularityLevel,
    CASE 
        WHEN pa.ScorePercentile > 0.9 THEN 'Top 10%'
        WHEN pa.ScorePercentile > 0.75 THEN 'Top 25%'
        WHEN pa.ScorePercentile > 0.5 THEN 'Top 50%'
        ELSE 'Below Median'
    END AS PerformanceBucket,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.PostId) AS CommentCountOnPost,
    (SELECT COUNT(DISTINCT UserId) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId IN (2, 3)) AS UniqueVoters
FROM TopUsers tu
INNER JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
LEFT JOIN AnswerQuality aq ON pa.PostId = aq.PostId
LEFT JOIN TagAnalysis ta ON pa.Tags LIKE '%' || ta.TagName || '%'
WHERE (pa.PostStatus = 'Answered' OR pa.PostStatus = 'Has Answers' OR pa.PostStatus = 'Unanswered')
  AND pa.Score IS NOT NULL
  AND pa.ViewCount IS NOT NULL
  AND pa.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 YEAR')
  AND pa.Score > 0
  AND tu.Reputation > 100
ORDER BY tu.Reputation DESC, pa.Score DESC, pa.DaysSinceLastActivity ASC
LIMIT 10000;