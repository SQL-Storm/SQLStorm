-- {"query": "2136.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1183} 

WITH RecursiveTagHierarchy AS (
    -- Recursive CTE to find related tags via tag wikis and excerpts
    SELECT t.Id, t.TagName, 1 AS Depth
    FROM Tags t
    WHERE t.Count > 1000 AND t.IsModeratorOnly = 0

    UNION ALL

    SELECT t2.Id, t2.TagName, r.Depth + 1
    FROM RecursiveTagHierarchy r
    JOIN Posts p ON p.Id = (CASE WHEN p.PostTypeId = 4 THEN p.Id ELSE NULL END)
    JOIN Tags t2 ON t2.ExcerptPostId = p.Id OR t2.WikiPostId = p.Id
    WHERE r.Depth < 3 AND t2.Count > 500 AND t2.IsModeratorOnly = 0
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotes,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) OVER () AS AvgQuestionScore,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 24) AS EditsMade
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ClosingReasonsStats AS (
    SELECT
        crt.Name AS CloseReason,
        COUNT(ph.Id) AS CloseVotesCount,
        COUNT(DISTINCT ph.PostId) AS ClosedPostsCount,
        AVG(EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate))) AS AvgCloseDelaySeconds
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id AND ph.PostHistoryTypeId = 10
    JOIN Posts p ON p.Id = ph.PostId AND p.ClosedDate IS NOT NULL
    GROUP BY crt.Name
),
TopScoredAnswersPerQuestion AS (
    SELECT DISTINCT ON (p.ParentId)
        p.ParentId AS QuestionId,
        p.Id AS AnswerId,
        p.Score,
        u.DisplayName AS AnswerOwner,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
    ORDER BY p.ParentId, p.Score DESC, p.CreationDate ASC
),
QuestionsWithBadges AS (
    SELECT DISTINCT p.Id AS QuestionId, b.Name AS BadgeName, b.Class AS BadgeClass
    FROM Posts p
    JOIN Badges b ON b.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND b.Class = 1 /* Gold badges only */
),
AggregatedStats AS (
    SELECT
        ua.UserId,
        ua.DisplayName AS UserName,
        ua.Reputation,
        ua.PostsCount,
        ua.BadgesCount,
        ua.UpVotes,
        ua.DownVotes,
        COALESCE(crs.CloseVotesCount, 0) AS TotalCloseVotes,
        COALESCE(crs.ClosedPostsCount, 0) AS TotalClosedPosts,
        COALESCE(crs.AvgCloseDelaySeconds, 0) AS AvgCloseDelaySeconds,
        tq.BadgeName,
        tq.BadgeClass,
        tsa.AnswerId,
        tsa.Score AS TopAnswerScore,
        tsa.AnswerOwner,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY tsa.Score DESC NULLS LAST) AS AnswerRank
    FROM UserActivity ua
    LEFT JOIN ClosingReasonsStats crs ON 1 = 1 -- Cartesian join intentional for benchmarking
    LEFT JOIN QuestionsWithBadges tq ON tq.QuestionId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
    )
    LEFT JOIN TopScoredAnswersPerQuestion tsa ON tsa.QuestionId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
    )
)
SELECT DISTINCT
    u.UserId,
    u.UserName,
    u.Reputation,
    u.PostsCount,
    u.BadgesCount,
    u.UpVotes,
    u.DownVotes,
    u.TotalCloseVotes,
    u.TotalClosedPosts,
    ROUND(u.AvgCloseDelaySeconds / 3600.0, 2) AS AvgCloseDelayHours,
    COALESCE(u.BadgeName, 'No Gold Badge') || CASE u.BadgeClass WHEN 1 THEN ' (Gold)' ELSE '' END AS ProminentBadge,
    CONCAT_WS(' / ', u.AnswerOwner, 'Top Answer Score:', COALESCE(CAST(u.TopAnswerScore AS VARCHAR), 'N/A')) AS TopAnswerInfo
FROM AggregatedStats u
WHERE u.AnswerRank = 1 OR u.AnswerRank IS NULL
ORDER BY u.Reputation DESC, u.PostsCount DESC, u.TopAnswerScore DESC NULLS LAST
LIMIT 100;
