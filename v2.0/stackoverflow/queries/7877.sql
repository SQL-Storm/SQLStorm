-- {"query": "7877.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1465}
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.Tags IS NOT NULL
    WHERE u.CreationDate >= TIMESTAMP '2010-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        TotalQuestionScore,
        TotalAnswerScore,
        LastPostDate,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC) as RankByScore,
        RANK() OVER (ORDER BY Reputation DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as RankByPostCount
    FROM UserPostStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as RelatedPosts,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreForTag
    FROM Tags t
    WHERE t.Count > 100
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(v.Id) as TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) as Favorites,
        STRING_AGG(DISTINCT vt.Name, ', ') as VoteTypes
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE u.CreationDate BETWEEN DATE '2015-01-01' AND DATE '2023-12-31'
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalQuestionScore,
    tu.TotalAnswerScore,
    tu.LastPostDate,
    tu.AllTags,
    tu.RankByScore,
    tu.RankByReputation,
    tu.RankByPostCount,
    COALESCE(ua.TotalVotes, 0) as TotalVotes,
    COALESCE(ua.UpVotes, 0) as UpVotes,
    COALESCE(ua.DownVotes, 0) as DownVotes,
    COALESCE(ua.Favorites, 0) as Favorites,
    COALESCE(ua.VoteTypes, 'None') as VoteTypes,
    ta.TagName,
    ta.Count,
    ta.RelatedPosts,
    ta.AvgScoreForTag,
    CASE WHEN tu.TotalPosts > 0 AND tu.QuestionCount > 0 THEN 
         ROUND((CAST(tu.AnswerCount AS DECIMAL) / NULLIF(CAST(tu.QuestionCount AS DECIMAL),0)), 2) 
         ELSE 0 END as AnswersPerQuestion,
    CASE WHEN tu.TotalQuestionScore > 0 THEN 
         ROUND((CAST(tu.TotalAnswerScore AS DECIMAL) / NULLIF(CAST(tu.TotalQuestionScore AS DECIMAL),0)), 2) 
         ELSE 0 END as AnswerScoreRatio,
    CASE WHEN tu.Reputation >= 10000 THEN 'High'
         WHEN tu.Reputation >= 5000 THEN 'Medium'
         WHEN tu.Reputation >= 1000 THEN 'Low'
         ELSE 'Very Low' END as ReputationLevel,
    CASE WHEN tu.RankByScore <= 50 THEN 'Top Scorer'
         WHEN tu.RankByReputation <= 50 THEN 'Top Reputable'
         WHEN tu.RankByPostCount <= 50 THEN 'Top Poster'
         ELSE 'Regular' END as UserClassification,
    LAG(tu.DisplayName) OVER (ORDER BY tu.RankByScore) as PreviousTopScorer,
    LEAD(tu.DisplayName) OVER (ORDER BY tu.RankByScore) as NextTopScorer,
    ROW_NUMBER() OVER (PARTITION BY CASE WHEN tu.Reputation >= 10000 THEN 'High'
                                       WHEN tu.Reputation >= 5000 THEN 'Medium'
                                       WHEN tu.Reputation >= 1000 THEN 'Low'
                                       ELSE 'Very Low' END
                      ORDER BY tu.TotalQuestionScore DESC) as RankWithinReputationTier,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = tu.UserId AND b.Class = 1) as GoldBadges,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = tu.UserId AND b.Class = 2) as SilverBadges,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = tu.UserId AND b.Class = 3) as BronzeBadges,
    NULLIF(LENGTH(tu.AllTags), 0) as TagsLength,
    CASE WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.Score > 100) THEN 'HasHighScorePosts'
         ELSE 'NoHighScorePosts' END as HighScoreIndicator
FROM TopUsers tu
LEFT JOIN UserActivity ua ON tu.UserId = ua.UserId
LEFT JOIN TagAnalysis ta ON tu.AllTags LIKE '%' || ta.TagName || '%'
WHERE (tu.Reputation > 5000 OR (tu.Reputation BETWEEN 1000 AND 5000 AND tu.TotalPosts > 10))
  AND (ta.RelatedPosts > 10 OR ta.RelatedPosts IS NULL)
  AND NOT EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = tu.UserId 
      AND p.CreationDate < TIMESTAMP '2020-01-01'
      AND p.PostTypeId = 1
)
ORDER BY tu.TotalQuestionScore DESC, tu.Reputation DESC, tu.TotalPosts DESC
LIMIT 500;