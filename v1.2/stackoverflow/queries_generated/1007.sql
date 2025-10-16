-- {"query": "1007.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1325} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS HierarchyPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
  UNION ALL
    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        parent.HierarchyPath || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.ExcerptPostId = parent.Id
    WHERE child.Id <> ALL(parent.HierarchyPath)
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COALESCE(SUM(v.VoteCount),0) AS TotalVotesReceived,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(COALESCE(p.Score,0)) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.DeletionDate IS NULL
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount
        FROM Votes
        WHERE VoteTypeId IN (2,3) -- upvotes and downvotes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC) AS UserRank,
        RANK() OVER (ORDER BY p.Score DESC NULLS LAST) AS GlobalRank,
        LEAD(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostScore,
        LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PrevPostScore
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
ClosedQuestionsWithReasons AS (
    SELECT
        ph.PostId,
        ph.UserId AS CloserUserId,
        u.DisplayName AS CloserName,
        crt.Name AS CloseReason,
        ph.CreationDate AS ClosedDate,
        p.Title,
        p.Score,
        p.ViewCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN Posts p ON p.Id = ph.PostId
    LEFT JOIN Users u ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId = 10 AND p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
)
SELECT DISTINCT
    ueu.DisplayName,
    ueu.Reputation,
    ueu.QuestionsPosted,
    ueu.AnswersPosted,
    ueu.CommentsMade,
    ueu.BadgeCount,
    ueu.TotalVotesReceived,
    ueu.AvgPostScore,
    pat.Id AS TopPostId,
    pat.Title AS TopPostTitle,
    pat.Score AS TopPostScore,
    pat.ViewCount AS TopPostViews,
    CASE
        WHEN pat.Tags IS NOT NULL THEN 
            array_to_string(ARRAY(
                SELECT unnest(string_to_array(substring(pat.Tags, 2, length(pat.Tags)-2), '><'))
                ORDER BY length(unnest)
                LIMIT 3
            ), ', ')
        ELSE NULL
    END AS TopPostTopTags,
    cqwr.CloseReason,
    cqwr.ClosedDate,
    cqwr.CloserName,
    ROW_NUMBER() OVER (PARTITION BY ueu.UserId ORDER BY pat.Score DESC NULLS LAST) AS UserTopPostRank
FROM UserEngagement ueu
LEFT JOIN LATERAL (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.Tags
    FROM Posts p
    WHERE p.OwnerUserId = ueu.UserId AND p.PostTypeId = 1 AND p.Score > 0
    ORDER BY p.Score DESC, p.CreationDate DESC
    LIMIT 1
) pat ON TRUE
LEFT JOIN ClosedQuestionsWithReasons cqwr ON cqwr.PostId = pat.Id
WHERE ueu.QuestionsPosted > 5 AND ueu.AnswersPosted > 10
AND ueu.Reputation > (
    SELECT AVG(Reputation) FROM Users
)
AND NOT EXISTS (
    SELECT 1 FROM Badges b2 WHERE b2.UserId = ueu.UserId AND b2.Class = 1
)
ORDER BY ueu.TotalVotesReceived DESC NULLS LAST, ueu.Reputation DESC
LIMIT 20

UNION ALL

SELECT DISTINCT
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    CASE 
        WHEN p.Tags IS NOT NULL THEN array_to_string(ARRAY(
            SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
            ORDER BY char_length(unnest) DESC
            LIMIT 2
        ), '; ')
        ELSE NULL
    END AS TopPostTopTags,
    NULL,
    NULL,
    NULL,
    NULL
FROM Posts p
WHERE p.PostTypeId = 2
  AND EXISTS (
    SELECT 1 FROM Votes v 
    WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate > p.CreationDate - INTERVAL '30 days'
  )
ORDER BY p.Score DESC
LIMIT 10;
