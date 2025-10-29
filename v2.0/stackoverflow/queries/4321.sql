WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
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
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount,0) ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) AS LastQuestionDate
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
        WHEN COALESCE(uqs.AvgQuestionScore, 0) > 50 THEN 'High Score Question'
        WHEN COALESCE(p.AnswerCount, 0) > 10 THEN 'Many Answers'
        ELSE 'Standard'
    END AS PostStatusCategory,
    CASE
        WHEN UPPER(COALESCE(p.Tags, '')) LIKE '%<SQL>%' THEN 'Contains SQL Tag'
        WHEN UPPER(COALESCE(p.Tags, '')) LIKE '%<PERFORMANCE>%' THEN 'Contains Performance Tag'
        ELSE 'Other Tags'
    END AS TagCategory,
    CASE
        WHEN LENGTH(COALESCE(REPLACE(p.Body, '<p>', ''), '')) < 50 THEN 'Short Body'
        WHEN POSITION('<code>' IN COALESCE(p.Body, '')) > 0 THEN 'Contains Code Snippet'
        ELSE 'Standard Body'
    END AS BodyAnalysis,
    (
        SELECT COUNT(c.Id)
        FROM Comments c
        WHERE c.PostId = p.Id AND COALESCE(c.Score,0) > 0
    ) AS PositiveCommentCount,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    CASE
        WHEN COALESCE(u.Location, '') LIKE '%New York%' THEN 'Based in New York'
        WHEN COALESCE(u.Location, '') LIKE '%London%' THEN 'Based in London'
        ELSE 'Other Location'
    END AS OwnerLocationCategory
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostEditSummaries pes ON p.Id = pes.PostId
LEFT JOIN UserQuestionStats uqs ON p.OwnerUserId = uqs.OwnerUserId
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
  AND (COALESCE(p.Score,0) > 10 OR COALESCE(p.CommentCount,0) > 5)
GROUP BY
    p.Id,
    pt.Name,
    u.DisplayName,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    pes.NumberOfEdits,
    pes.LastEditDate,
    uqs.QuestionCount,
    uqs.TotalQuestionViews,
    uqs.AvgQuestionScore,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.AnswerCount,
    p.Tags,
    p.Body,
    u.Reputation,
    u.Location
ORDER BY
    PostStatusCategory,
    TagCategory DESC,
    OwnerReputation DESC,
    LastActivityOrEditDate DESC
LIMIT 100;