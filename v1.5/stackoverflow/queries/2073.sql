-- {"query": "2073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 607} 
WITH HighReputationUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > (
        SELECT AVG(Reputation) FROM Users
    )
),
TopQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.Score, p.ViewCount, p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 10
),
RecentBadgeUsers AS (
    SELECT DISTINCT b.UserId
    FROM Badges b
    WHERE b.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
UserPostInteractions AS (
    SELECT 
        h.UserId,
        h.PostId,
        ROW_NUMBER() OVER (PARTITION BY h.UserId ORDER BY h.CreationDate DESC) AS InteractionRank
    FROM PostHistory h
    WHERE h.PostHistoryTypeId IN (4, 5, 6)
),
LinkedQuestions AS (
    SELECT DISTINCT 
        p.Id AS SourceQuestionId, 
        pl.RelatedPostId AS RelatedQuestionId, 
        lt.Name AS LinkType
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE p.PostTypeId = 1 
      AND pl.LinkTypeId = 1
),
PerformanceBenchmark AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        hru.Reputation, 
        tq.QuestionId, 
        tq.Title, 
        tq.Score, 
        tq.ViewCount, 
        lq.RelatedQuestionId, 
        ub.InteractionRank,
        COALESCE(ub.InteractionRank, 0) + COALESCE(tq.Score, 0) AS PerformanceScore
    FROM HighReputationUsers hru
    LEFT JOIN Users u ON hru.Id = u.Id
    LEFT JOIN TopQuestions tq ON tq.OwnerUserId = u.Id
    LEFT JOIN UserPostInteractions ub ON ub.UserId = u.Id AND ub.InteractionRank = 1
    LEFT JOIN LinkedQuestions lq ON lq.SourceQuestionId = tq.QuestionId
    WHERE u.Id IN (SELECT UserId FROM RecentBadgeUsers)
      AND (ub.InteractionRank IS NOT NULL OR tq.Score > 0)
      AND COALESCE(tq.Title, '') LIKE '%SQL%'
),
RankedPerformance AS (
    SELECT 
        UserId, 
        DisplayName, 
        PerformanceScore,
        RANK() OVER (ORDER BY PerformanceScore DESC) AS Rank
    FROM PerformanceBenchmark
)
SELECT 
    rp.UserId,
    rp.DisplayName,
    rp.PerformanceScore,
    rp.Rank,
    u.LastAccessDate
FROM RankedPerformance rp
JOIN Users u ON rp.UserId = u.Id
WHERE rp.Rank <= 10
ORDER BY rp.Rank;