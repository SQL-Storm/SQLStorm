-- {"query": "4524.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1247} 

WITH RECURSIVE PostHierarchy AS (
    -- Base case: Select top-level questions
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.Title,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate) as rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL

    UNION ALL

    -- Recursive step: Select answers for questions
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        0 as AnswerCount, -- Answers don't have their own answer count in this context
        p.Title, -- For answers, this might be NULL, or not relevant
        ROW_NUMBER() OVER (ORDER BY p.CreationDate) as rn
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE p.PostTypeId = 2
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.ViewCount) AS AverageViewCount,
        -- Correlated subquery to find the number of badges for each user
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        -- Using a window function to rank users by reputation within their creation date month
        RANK() OVER (PARTITION BY DATE_TRUNC('month', u.CreationDate) ORDER BY u.Reputation DESC) AS ReputationRankOfMonth
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        -- NULL logic: If a post has no votes, consider it as having a score of 0
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN v.VoteTypeId ELSE 0 END), 0) AS NetVoteScore,
        -- String expression to indicate if the post has been closed
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'CLOSED' ELSE 'OPEN' END AS PostStatus,
        -- Using window function to calculate the running total of scores for posts by the same owner
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS RunningScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.ClosedDate, p.OwnerUserId, p.CreationDate
)
SELECT
    ph.Id AS PostId,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    -- Complicated expression: Calculate post age in days and add a factor based on score and answer count
    (JULIANDAY('now') - JULIANDAY(ph.CreationDate)) + (ph.Score * 0.01) + (ph.AnswerCount * 0.1) AS WeightedPostAge,
    ups.QuestionCount,
    ups.AnswerCount AS UserAnswerCount,
    ups.TotalScore AS UserTotalScore,
    ups.LastPostDate,
    ups.AverageViewCount,
    ups.BadgeCount,
    ups.ReputationRankOfMonth,
    pe.CommentCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.PostStatus,
    pe.RunningScore,
    -- Set operator: Union of posts that are either closed or have more than 1000 score
    (SELECT 'HIGH_SCORE' FROM Posts p2 WHERE p2.Id = ph.Id AND p2.Score > 1000
     UNION
     SELECT 'CLOSED_POST' FROM Posts p3 WHERE p3.Id = ph.Id AND p3.ClosedDate IS NOT NULL) AS PostClassification,
    -- Using a subquery to get the tag names from the 'Tags' column
    (SELECT GROUP_CONCAT(tag, ', ') FROM (SELECT SUBSTR(tag, 2, INSTR(tag, '>') - 2) AS tag FROM (SELECT REGEXP_SPLIT_TO_TABLE(REPLACE(REPLACE(ph.Tags, '<', '>'), '><'), '>') AS tag) WHERE tag <> '') AS tag_list) AS FormattedTags
FROM PostHierarchy ph
JOIN PostTypes pt ON ph.PostTypeId = pt.Id
LEFT JOIN UserPostStats ups ON ph.OwnerUserId = ups.UserId
LEFT JOIN PostEngagement pe ON ph.Id = pe.PostId
WHERE ph.rn BETWEEN 100 AND 200 -- Limiting results for benchmarking
ORDER BY ph.CreationDate DESC;
