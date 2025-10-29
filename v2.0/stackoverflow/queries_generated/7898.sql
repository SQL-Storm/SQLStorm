-- {"query": "7898.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2146} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN AVG(p.Score)
            ELSE 0 
        END AS AveragePostScore,
        CASE 
            WHEN COUNT(DISTINCT b.Id) > 0 THEN 
                CASE 
                    WHEN COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) > 0 THEN 'Gold'
                    WHEN COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) > 0 THEN 'Silver'
                    WHEN COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) > 0 THEN 'Bronze'
                    ELSE 'None'
                END
            ELSE 'None'
        END AS TopBadgeTier,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2)
            ELSE 0 
        END AS AnswerCountComputed,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 
                (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId)
            ELSE 0 
        END AS AcceptedAnswerScore
    FROM Posts p
    WHERE p.Id IS NOT NULL
    AND (p.PostTypeId IN (1, 2) OR (p.PostTypeId = 1 AND p.AnswerCount > 0))
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS PostsWithTag,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS AvgScoreForTag,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS LastPostWithTag
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
ComplexUserAnalysis AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.DisplayName,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.BadgeCount,
        us.VoteCount,
        us.AveragePostScore,
        us.TotalScore,
        us.TotalViews,
        us.TopBadgeTier,
        us.AllTags,
        CASE 
            WHEN us.PostCount > 0 AND us.AnswerCount > 0 THEN 
                (us.AnswerCount * 1.0 / us.PostCount) 
            ELSE 0 
        END AS AnswerRatio,
        CASE 
            WHEN us.VoteCount > 0 AND us.Score > 0 THEN 
                (us.VoteCount * 1.0 / us.Score)
            ELSE 0 
        END AS VotePerScoreRatio
    FROM UserStats us
),
FinalAnalysis AS (
    SELECT 
        cua.UserId,
        cua.DisplayName,
        cua.Reputation,
        cua.PostCount,
        cua.QuestionCount,
        cua.AnswerCount,
        cua.BadgeCount,
        cua.VoteCount,
        cua.AveragePostScore,
        cua.TotalScore,
        cua.TotalViews,
        cua.TopBadgeTier,
        cua.AnswerRatio,
        cua.VotePerScoreRatio,
        ps.PostId,
        ps.Title,
        ps.Body,
        ps.Score AS PostScore,
        ps.ViewCount AS PostViewCount,
        ps.CreationDate AS PostCreationDate,
        ps.Tags AS PostTags,
        ps.AnswerCountComputed,
        ps.AcceptedAnswerScore,
        ta.TagName,
        ta.Count AS TagCount,
        ta.AvgScoreForTag,
        ta.LastPostWithTag,
        CASE 
            WHEN ps.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.PostId)
            ELSE 0 
        END AS CommentCount,
        CASE 
            WHEN ps.PostTypeId = 2 AND ps.AcceptedAnswerId IS NOT NULL THEN 
                'Accepted'
            WHEN ps.PostTypeId = 2 AND ps.AcceptedAnswerId IS NULL THEN 
                'Not Accepted'
            ELSE 'N/A'
        END AS AnswerStatus,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate DESC) AS PostRank,
        RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY us.Reputation DESC) AS ReputationRank
    FROM ComplexUserAnalysis cua
    JOIN PostStats ps ON cua.UserId = ps.OwnerUserId
    LEFT JOIN TagAnalysis ta ON ps.Tags LIKE '%' || ta.TagName || '%'
    LEFT JOIN UserStats us ON cua.UserId = us.UserId
    WHERE ps.Score >= 0
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.BadgeCount,
    fa.VoteCount,
    fa.AveragePostScore,
    fa.TotalScore,
    fa.TotalViews,
    fa.TopBadgeTier,
    fa.AnswerRatio,
    fa.VotePerScoreRatio,
    fa.PostId,
    fa.Title,
    CASE 
        WHEN LENGTH(fa.Body) > 200 THEN LEFT(fa.Body, 200) || '...'
        ELSE fa.Body 
    END AS BodyPreview,
    fa.PostScore,
    fa.PostViewCount,
    fa.PostCreationDate,
    fa.PostTags,
    fa.AnswerCountComputed,
    fa.AcceptedAnswerScore,
    fa.TagName,
    fa.TagCount,
    fa.AvgScoreForTag,
    fa.LastPostWithTag,
    fa.CommentCount,
    fa.AnswerStatus,
    fa.PostRank,
    fa.ScoreRank,
    fa.ReputationRank,
    CASE 
        WHEN fa.Reputation > 1000 AND fa.PostCount > 10 THEN 'Active Pro'
        WHEN fa.Reputation > 500 AND fa.PostCount > 5 THEN 'Active User'
        WHEN fa.Reputation > 100 THEN 'Regular User'
        ELSE 'New User'
    END AS UserCategory,
    CASE 
        WHEN fa.AnswerCount >= 10 AND fa.AnswerRatio >= 0.7 THEN 'High Quality Answerer'
        WHEN fa.AnswerCount >= 5 AND fa.AnswerRatio >= 0.5 THEN 'Good Answerer'
        ELSE 'Regular Answerer'
    END AS AnswerQuality,
    CASE 
        WHEN fa.PostScore > (SELECT AVG(PostScore) FROM FinalAnalysis) THEN 'Above Average Score'
        WHEN fa.PostScore < (SELECT AVG(PostScore) FROM FinalAnalysis) THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScoreLevel,
    COALESCE(fa.LastPostWithTag, 'No Recent Tag Posts') AS RecentTagActivity,
    CASE 
        WHEN fa.ReputationRank = 1 THEN 'Top Contributor'
        WHEN fa.ReputationRank <= 10 THEN 'Top 10 Contributor'
        WHEN fa.ReputationRank <= 50 THEN 'Top 50 Contributor'
        ELSE 'Regular Contributor'
    END AS ReputationStatus,
    (SELECT COUNT(*) FROM FinalAnalysis fa2 WHERE fa2.UserId = fa.UserId AND fa2.PostCreationDate >= CURRENT_TIMESTAMP - INTERVAL '7 days') AS RecentPosts7Days,
    (SELECT COUNT(*) FROM FinalAnalysis fa3 WHERE fa3.UserId = fa.UserId AND fa3.PostScore > 10) AS HighScorePosts,
    (SELECT STRING_AGG(DISTINCT fa4.TagName, ', ') FROM FinalAnalysis fa4 WHERE fa4.UserId = fa.UserId) AS UserTagFocus,
    CASE 
        WHEN fa.AnswerRatio > 0.8 THEN 'Experienced Answerer'
        WHEN fa.AnswerRatio > 0.6 THEN 'Active Answerer'
        WHEN fa.AnswerRatio > 0.4 THEN 'Occasional Answerer'
        ELSE 'Rare Answerer'
    END AS AnsweringFrequency,
    NULLIF(fa.PostCount, 0) / NULLIF(fa.QuestionCount, 0) AS AnswerToQuestionRatio
FROM FinalAnalysis fa
WHERE fa.PostId IS NOT NULL
AND (fa.PostScore > 0 OR fa.PostScore IS NULL)
AND fa.Reputation > 0
AND (fa.Reputation >= 100 OR fa.PostCount > 0)
ORDER BY 
    fa.ReputationRank ASC,
    fa.ScoreRank ASC,
    fa.PostCreationDate DESC
LIMIT 10000;