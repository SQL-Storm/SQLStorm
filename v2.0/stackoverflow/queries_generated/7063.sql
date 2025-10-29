-- {"query": "7063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1635} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.Score) AS MaxPostScore,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT p.Tags, '; ') AS AllTags,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        CASE 
            WHEN COUNT(p.Id) = 0 THEN 'No Posts'
            WHEN COUNT(p.Id) > 100 THEN 'Active'
            WHEN COUNT(p.Id) > 50 THEN 'Moderately Active'
            ELSE 'Occasional'
        END AS ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' 
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
        MaxPostScore,
        AvgPostScore,
        AllTags,
        CommentCount,
        BadgeCount,
        LastPostDate,
        ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS RankByReputation,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC) AS RankByPosts,
        ROW_NUMBER() OVER (ORDER BY BadgeCount DESC) AS RankByBadges
    FROM UserPostStats
),
UserScores AS (
    SELECT 
        UserId,
        SUM(CASE 
            WHEN VoteTypeId = 2 THEN 1 
            WHEN VoteTypeId = 3 THEN -1 
            ELSE 0 
        END) AS NetVotes,
        COUNT(*) AS TotalVotes
    FROM Votes
    GROUP BY UserId
),
ComplexTags AS (
    SELECT 
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
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS QuestionCountWithTag,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS AvgScoreForTag
    FROM Tags t
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 'Answer'
            ELSE 'Other'
        END AS PostCategory,
        CASE 
            WHEN p.Score >= 10 THEN 'Highly Voted'
            WHEN p.Score >= 1 THEN 'Moderately Voted'
            ELSE 'Low Voted'
        END AS VoteLevel,
        COALESCE(
            (SELECT b.Name FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Name = 'Good Question' AND b.Date >= p.CreationDate),
            'No Special Badge'
        ) AS SpecialAward
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
FinalAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.MaxPostScore,
        tu.AvgPostScore,
        tu.AllTags,
        tu.CommentCount,
        tu.BadgeCount,
        tu.LastPostDate,
        tu.ActivityLevel,
        tu.RankByReputation,
        tu.RankByPosts,
        tu.RankByBadges,
        us.NetVotes,
        us.TotalVotes,
        ct.TagName,
        ct.Count AS TagCount,
        ct.TagPopularity,
        ct.QuestionCountWithTag,
        ct.AvgScoreForTag,
        pa.Id AS PostId,
        pa.Title AS PostTitle,
        pa.PostCategory,
        pa.Score AS PostScore,
        pa.ViewCount AS PostViewCount,
        pa.CreationDate AS PostCreationDate,
        pa.VoteLevel,
        pa.SpecialAward,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY pa.CreationDate DESC) AS RecentPostRank,
        DENSE_RANK() OVER (ORDER BY pa.Score DESC) AS PostRankByScore,
        RANK() OVER (ORDER BY pa.ViewCount DESC) AS PostRankByViews
    FROM TopUsers tu
    LEFT JOIN UserScores us ON tu.UserId = us.UserId
    LEFT JOIN ComplexTags ct ON ct.TagName IN (
        SELECT UNNEST(STRING_TO_ARRAY(tu.AllTags, '; ')) 
        WHERE UNNEST(STRING_TO_ARRAY(tu.AllTags, '; ')) IS NOT NULL
    )
    LEFT JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
    WHERE tu.Reputation > 1000 
    AND tu.TotalPosts > 5
    AND (tu.BadgeCount > 5 OR tu.CommentCount > 20)
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    QuestionCount,
    AnswerCount,
    MaxPostScore,
    AvgPostScore,
    AllTags,
    CommentCount,
    BadgeCount,
    LastPostDate,
    ActivityLevel,
    RankByReputation,
    RankByPosts,
    RankByBadges,
    NetVotes,
    TotalVotes,
    TagName,
    TagCount,
    TagPopularity,
    QuestionCountWithTag,
    AvgScoreForTag,
    PostId,
    PostTitle,
    PostCategory,
    PostScore,
    PostViewCount,
    PostCreationDate,
    VoteLevel,
    SpecialAward,
    RecentPostRank,
    PostRankByScore,
    PostRankByViews,
    CASE 
        WHEN RecentPostRank <= 3 THEN 'Recent Top 3'
        WHEN RecentPostRank <= 10 THEN 'Recent Top 10'
        ELSE 'Other'
    END AS RecentPostClassification,
    CASE 
        WHEN PostRankByScore <= 100 THEN 'Top Scoring Post'
        WHEN PostRankByViews <= 100 THEN 'Top Viewed Post'
        ELSE 'Regular Post'
    END AS PostImportance,
    (NetVotes * 100.0 / NULLIF(TotalVotes, 0)) AS NetVotePercentage,
    (COALESCE(AvgScoreForTag, 0) * 100.0 / NULLIF(MaxPostScore, 0)) AS TagScoreRatio,
    CONCAT(UserId, '-', DisplayName, '-', PostId) AS CompositeKey
FROM FinalAnalysis
WHERE PostId IS NOT NULL
ORDER BY Reputation DESC, TotalPosts DESC, NetVotes DESC, NetVotePercentage DESC
LIMIT 1000;