-- {"query": "7366.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1417} 
WITH UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) as RowNum,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(p.Score) AS FLOAT) / NULLIF(COUNT(DISTINCT p.Id), 0)
            ELSE 0 
        END as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
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
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        LastCommentDate,
        AvgPostScore,
        AllTags,
        RANK() OVER (ORDER BY Reputation DESC, PostCount DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY AvgPostScore DESC) as ScoreRank
    FROM UserActivity
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
        u.DisplayName as OwnerName,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        DATEDIFF('DAY', p.CreationDate, COALESCE(p.ClosedDate, NOW())) as DaysSinceCreation,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Low Voted'
            ELSE 'No Votes'
        END as VoteCategory,
        CASE 
            WHEN p.AnswerCount = 0 THEN 'No Answers'
            WHEN p.AnswerCount < 3 THEN 'Few Answers'
            WHEN p.AnswerCount < 10 THEN 'Moderate Answers'
            ELSE 'Many Answers'
        END as AnswerCategory,
        COALESCE(ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) as UserPostRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2010-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityCategory,
        CAST(t.Count AS FLOAT) / NULLIF((SELECT MAX(Count) FROM Tags), 0) * 100 as PercentileRank
    FROM Tags t
)
SELECT 
    'Overall Statistics' as Category,
    COUNT(DISTINCT u.Id) as TotalUsers,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT t.Id) as TotalTags,
    NULL as UserId,
    NULL as DisplayName,
    NULL as Reputation
FROM Users u
FULL OUTER JOIN Posts p ON 1=1
FULL OUTER JOIN Comments c ON 1=1
FULL OUTER JOIN Badges b ON 1=1
FULL OUTER JOIN Tags t ON 1=1

UNION ALL

SELECT 
    'Top Performing Users' as Category,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    tu.UserId,
    tu.DisplayName,
    tu.Reputation
FROM TopUsers tu
WHERE tu.ReputationRank <= 10

UNION ALL

SELECT 
    'High Score Posts' as Category,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    pa.PostId as UserId,
    pa.Title,
    pa.Score
FROM PostAnalysis pa
WHERE pa.VoteCategory = 'Highly Voted'
ORDER BY pa.Score DESC
LIMIT 10

UNION ALL

SELECT 
    'Popular Tags Analysis' as Category,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    ta.TagName as UserId,
    ta.TagName as DisplayName,
    ta.Count as Reputation
FROM TagAnalysis ta
WHERE ta.PopularityCategory = 'Popular'
ORDER BY ta.Count DESC
LIMIT 15

UNION ALL

SELECT 
    'User Activity Summary' as Category,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    ua.UserId,
    ua.DisplayName,
    ua.Reputation
FROM UserActivity ua
WHERE ua.PostCount > 100 AND ua.CommentCount > 50
ORDER BY ua.Reputation DESC
LIMIT 5

UNION ALL

SELECT 
    'Question Analysis' as Category,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    pa.PostId as UserId,
    pa.Title,
    pa.AnswerCount
FROM PostAnalysis pa
WHERE pa.PostType = 'Question' AND pa.AnswerCategory IN ('Many Answers', 'Moderate Answers')
ORDER BY pa.AnswerCount DESC
LIMIT 10

UNION ALL

SELECT 
    'Recent Activity' as Category,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    pa.PostId as UserId,
    pa.Title,
    DATEDIFF('DAY', pa.CreationDate, NOW()) as CreationDays
FROM PostAnalysis pa
WHERE pa.CreationDate >= DATEADD('DAY', -30, NOW())
ORDER BY pa.CreationDate DESC
LIMIT 20;