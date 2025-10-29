-- {"query": "4321.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1048} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditSummaries AS (
    SELECT
        rpe.PostId,
        rpe.UserId,
        u.DisplayName AS EditorDisplayName,
        rpe.CreationDate AS LastEditDate,
        COUNT(rpe.PostId) AS NumberOfEdits
    FROM RankedPostEdits rpe
    JOIN Users u ON rpe.UserId = u.Id
    WHERE rpe.rn = 1
    GROUP BY rpe.PostId, rpe.UserId, u.DisplayName, rpe.CreationDate
),
UserQuestionStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate ELSE NULL END) AS LastQuestionDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    u.DisplayName AS OwnerDisplayName,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COALESCE(pes.NumberOfEdits, 0) AS EditCount,
    COALESCE(pes.LastEditDate, p.CreationDate) AS LastActivityOrEditDate,
    COALESCE(uqs.QuestionCount, 0) AS UserQuestionsAsked,
    COALESCE(uqs.TotalQuestionViews, 0) AS UserTotalQuestionViews,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN uqs.AvgQuestionScore > 50 THEN 'High Score Question'
        WHEN p.AnswerCount > 10 THEN 'Many Answers'
        ELSE 'Standard'
    END AS PostStatusCategory,
    CASE
        WHEN UPPER(p.Tags) LIKE '%<sql>%' THEN 'Contains SQL Tag'
        WHEN UPPER(p.Tags) LIKE '%<performance>%' THEN 'Contains Performance Tag'
        ELSE 'Other Tags'
    END AS TagCategory,
    CASE
        WHEN LENGTH(REPLACE(p.Body, '<p>', '')) < 50 THEN 'Short Body'
        WHEN INSTR(p.Body, '<code>') > 0 THEN 'Contains Code Snippet'
        ELSE 'Standard Body'
    END AS BodyAnalysis,
    -- Correlated subquery to find the number of comments on this post with score > 0
    (
        SELECT COUNT(c.Id)
        FROM Comments c
        WHERE c.PostId = p.Id AND c.Score > 0
    ) AS PositiveCommentCount,
    -- Using LEFT JOIN to include posts that might not have any edits
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    -- Checking for specific string patterns in the owner's location
    CASE
        WHEN u.Location LIKE '%New York%' THEN 'Based in New York'
        WHEN u.Location LIKE '%London%' THEN 'Based in London'
        ELSE 'Other Location'
    END AS OwnerLocationCategory
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostEditSummaries pes ON p.Id = pes.PostId
LEFT JOIN UserQuestionStats uqs ON p.OwnerUserId = uqs.OwnerUserId
WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
  AND p.CreationDate >= DATE('now', '-365 day') -- Last year's posts
  AND (p.Score > 10 OR p.CommentCount > 5) -- Filter for active posts
ORDER BY
    PostStatusCategory,
    TagCategory DESC,
    OwnerReputation DESC,
    LastActivityOrEditDate DESC
LIMIT 100;