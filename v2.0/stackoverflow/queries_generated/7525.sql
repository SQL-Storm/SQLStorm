-- {"query": "7525.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2186} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) * 10 AS ComplexScore,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 100 THEN 'Highly_Voted_Question'
            WHEN p.PostTypeId = 1 AND p.Score BETWEEN 10 AND 100 THEN 'Medium_Voted_Question'
            WHEN p.PostTypeId = 1 AND p.Score < 10 THEN 'Low_Voted_Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostCategory,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS TagList,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentPostNumber,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT c.PostId) AS CommentCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 5000 THEN 'Intermediate'
            WHEN u.Reputation > 1000 THEN 'Beginner'
            ELSE 'Newbie'
        END AS UserLevel,
        DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) AS AccountAgeDays,
        (u.UpVotes - u.DownVotes) AS NetVotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END AS TagPopularity,
        COALESCE(t.Count, 0) * 1.5 AS AdjustedCount,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS PrevCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS RankByCount
    FROM Tags t
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.CommentCount,
        ps.AnswerCount,
        ps.ComplexScore,
        ps.PostCategory,
        ps.TagList,
        ps.TagArray,
        ps.ViewRank,
        ps.RecentPostNumber,
        ps.PreviousScore,
        ps.NextScore,
        ps.AvgScoreByType,
        CASE 
            WHEN ps.ComplexScore > (SELECT AVG(ComplexScore) FROM PostStats) THEN 'Above_Avg'
            WHEN ps.ComplexScore < (SELECT AVG(ComplexScore) FROM PostStats) THEN 'Below_Avg'
            ELSE 'Avg'
        END AS ScoreComparison,
        COALESCE(
            CASE WHEN ps.PostTypeId = 1 THEN 
                (SELECT TOP 1 p.Score FROM Posts p WHERE p.ParentId = ps.Id ORDER BY p.CreationDate ASC)
            END, 0
        ) AS FirstAnswerScore,
        COALESCE(
            CASE WHEN ps.PostTypeId = 1 THEN 
                (SELECT TOP 1 p.Score FROM Posts p WHERE p.ParentId = ps.Id ORDER BY p.CreationDate DESC)
            END, 0
        ) AS LastAnswerScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT TOP 1 v.CreationDate FROM Votes v WHERE v.PostId = ps.Id ORDER BY v.CreationDate ASC) AS FirstVoteDate,
        (SELECT TOP 1 v.CreationDate FROM Votes v WHERE v.PostId = ps.Id ORDER BY v.CreationDate DESC) AS LastVoteDate,
        COALESCE(ps.Score, 0) + COALESCE(ps.ViewCount, 0) + COALESCE(ps.CommentCount, 0) AS CompositeMetric,
        CASE 
            WHEN ps.TagArray IS NOT NULL AND ARRAY_LENGTH(ps.TagArray) > 0 THEN 
                (SELECT COUNT(*) FROM UNNEST(ps.TagArray) AS t WHERE LENGTH(t) > 5)
            ELSE 0 
        END AS LongTagCount,
        CASE WHEN ps.PostTypeId = 1 THEN 'Q' ELSE 'A' END AS QuestionOrAnswer,
        CASE 
            WHEN ps.Score > 100 AND ps.AnswerCount > 5 THEN 'Highly_Interactive'
            WHEN ps.Score > 50 AND ps.AnswerCount > 3 THEN 'Moderately_Interactive'
            WHEN ps.Score > 0 AND ps.AnswerCount > 1 THEN 'Low_Interactive'
            ELSE 'Inactive'
        END AS InteractionLevel
    FROM PostStats ps
),
CrossJoinAnalysis AS (
    SELECT 
        cpa.Id AS PostId,
        cpa.PostTypeId,
        cpa.Score,
        cpa.ViewCount,
        cpa.ComplexScore,
        cpa.PostCategory,
        cpa.CompositeMetric,
        cpa.InteractionLevel,
        ua.UserId,
        ua.Reputation,
        ua.UserLevel,
        ua.NetVotes,
        ta.Id AS TagId,
        ta.TagName,
        ta.Count AS TagCount,
        ta.TagPopularity,
        CASE 
            WHEN cpa.PostCategory = 'Highly_Voted_Question' AND ua.UserLevel = 'Expert' AND ta.TagPopularity = 'Popular' THEN 'Targeted_Opportunity'
            WHEN cpa.PostCategory = 'Answer' AND ua.NetVotes > 1000 AND ta.TagPopularity = 'Popular' THEN 'High_Value_Answer'
            WHEN cpa.PostCategory = 'Highly_Voted_Question' AND ua.Reputation > 10000 AND ta.TagPopularity = 'Moderate' THEN 'Premium_Question'
            ELSE 'Regular_Case'
        END AS OpportunityClassification,
        MOD(cpa.Id + ua.UserId + ta.Id, 1000) AS HashKey
    FROM ComplexPostAnalysis cpa
    CROSS JOIN UserActivity ua
    LEFT JOIN TagAnalysis ta ON (cpa.TagArray IS NOT NULL AND ta.TagName IN (SELECT UNNEST(cpa.TagArray)))
    WHERE cpa.CompositeMetric > 0
    AND ua.Reputation > 100
    AND ua.NetVotes > 10
    AND ta.Count > 10
)
SELECT 
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT PostId) AS UniquePosts,
    COUNT(DISTINCT UserId) AS UniqueUsers,
    COUNT(DISTINCT TagId) AS UniqueTags,
    AVG(Score) AS AvgScore,
    MAX(CompositeMetric) AS MaxCompositeMetric,
    MIN(CompositeMetric) AS MinCompositeMetric,
    AVG(Reputation) AS AvgReputation,
    AVG(NetVotes) AS AvgNetVotes,
    AVG(TagCount) AS AvgTagCount,
    STRING_AGG(DISTINCT InteractionLevel, ', ') AS InteractionLevels,
    STRING_AGG(DISTINCT UserLevel, ', ') AS UserLevels,
    STRING_AGG(DISTINCT TagPopularity, ', ') AS TagPopularityLevels,
    STRING_AGG(DISTINCT OpportunityClassification, ', ') AS OpportunityClassifications
FROM CrossJoinAnalysis
WHERE 
    (OpportunityClassification = 'Targeted_Opportunity' OR 
     OpportunityClassification = 'High_Value_Answer' OR 
     OpportunityClassification = 'Premium_Question')
    AND CompositeMetric > (
        SELECT AVG(CompositeMetric) 
        FROM CrossJoinAnalysis 
        WHERE OpportunityClassification IN ('Targeted_Opportunity', 'High_Value_Answer', 'Premium_Question')
    )
    AND EXISTS (SELECT 1 FROM Posts p WHERE p.Id = CrossJoinAnalysis.PostId AND p.CreationDate > '2020-06-01')
    AND EXISTS (SELECT 1 FROM Users u WHERE u.Id = CrossJoinAnalysis.UserId AND u.CreationDate > '2019-01-01')
    AND EXISTS (SELECT 1 FROM Tags t WHERE t.Id = CrossJoinAnalysis.TagId AND t.Count > 50)
GROUP BY 
    PostCategory,
    TagPopularity
HAVING 
    COUNT(*) > 100
    AND AVG(CompositeMetric) > 500
    AND MAX(CompositeMetric) > 2000
ORDER BY 
    COUNT(*) DESC,
    AVG(CompositeMetric) DESC
LIMIT 50;