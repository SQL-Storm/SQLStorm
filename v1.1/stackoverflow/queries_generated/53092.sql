-- {"query": "53092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1059} 

WITH RECURSIVE PostHierarchy AS (
    SELECT 
        Id, 
        ParentId, 
        OwnerUserId, 
        Score, 
        CreationDate, 
        PostTypeId, 
        0 AS Depth
    FROM Posts
    WHERE PostTypeId = 1  -- Questions
    UNION ALL
    SELECT 
        p.Id, 
        p.ParentId, 
        p.OwnerUserId, 
        p.Score, 
        p.CreationDate, 
        p.PostTypeId, 
        ph.Depth + 1
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE p.PostTypeId = 2  -- Answers
),
ActiveUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 50 AND SUM(p.Score) > 1000
),
TagAnalysis AS (
    SELECT 
        t.Id AS TagId, 
        t.TagName, 
        t.Count AS TagUsage,
        COUNT(DISTINCT p.Id) AS RecentQuestions,
        SUM(p.ViewCount) AS TotalViews
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY t.Id, t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 100
),
VoteSummary AS (
    SELECT 
        v.PostId, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes v
    GROUP BY v.PostId
),
EditHistory AS (
    SELECT 
        ph.PostId, 
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)  -- Edits and rollbacks
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 5
),
CommentActivity AS (
    SELECT 
        c.PostId, 
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
    HAVING COUNT(c.Id) > 10
),
BenchmarkData AS (
    SELECT 
        ph.Id AS PostId,
        ph.ParentId,
        ph.OwnerUserId,
        ph.Score,
        ph.CreationDate,
        ph.Depth,
        au.Reputation AS UserReputation,
        au.DisplayName AS UserName,
        au.PostCount AS UserPostCount,
        au.TotalScore AS UserTotalScore,
        ta.TagName AS PrimaryTag,
        ta.TagUsage,
        ta.RecentQuestions,
        ta.TotalViews,
        vs.Upvotes,
        vs.Downvotes,
        vs.UniqueVoters,
        eh.EditCount,
        eh.LastEditDate,
        ca.CommentCount,
        ca.AvgCommentScore,
        ROW_NUMBER() OVER (PARTITION BY ph.ParentId ORDER BY ph.Score DESC) AS AnswerRank,
        DENSE_RANK() OVER (ORDER BY ph.Score DESC) AS GlobalScoreRank
    FROM PostHierarchy ph
    INNER JOIN ActiveUsers au ON ph.OwnerUserId = au.UserId
    LEFT JOIN Posts p ON ph.Id = p.Id
    LEFT JOIN TagAnalysis ta ON p.Tags LIKE '%' || ta.TagName || '%'
    LEFT JOIN VoteSummary vs ON ph.Id = vs.PostId
    LEFT JOIN EditHistory eh ON ph.Id = eh.PostId
    LEFT JOIN CommentActivity ca ON ph.Id = ca.PostId
    WHERE ph.Depth <= 5 AND ph.Score > 10
)
SELECT 
    PostId,
    ParentId,
    OwnerUserId,
    Score,
    CreationDate,
    Depth,
    UserReputation,
    UserName,
    UserPostCount,
    UserTotalScore,
    PrimaryTag,
    TagUsage,
    RecentQuestions,
    TotalViews,
    Upvotes,
    Downvotes,
    UniqueVoters,
    EditCount,
    LastEditDate,
    CommentCount,
    AvgCommentScore,
    AnswerRank,
    GlobalScoreRank
FROM BenchmarkData
WHERE GlobalScoreRank <= 1000
ORDER BY GlobalScoreRank, AnswerRank;
