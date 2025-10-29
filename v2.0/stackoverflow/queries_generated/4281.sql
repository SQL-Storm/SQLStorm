-- {"query": "4281.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1303} 

WITH RankedUserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScoreSum,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) DESC, COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) DESC) AS AnswerRank,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) DESC) AS QuestionRankForUser
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Id > 0
    GROUP BY
        u.Id, u.DisplayName
),
HighReputationUsers AS (
    SELECT
        Id,
        DisplayName,
        Reputation
    FROM
        Users
    WHERE
        Reputation >= 10000
),
TopAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS AnswerOrderForQuestion
    FROM
        Posts p
    WHERE
        p.PostTypeId = 2 AND p.Score > 50
),
RecentEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS LatestEditRank
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6)
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        pt.Name AS PostTypeName,
        COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ph.Text AS LastEditComment,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus
    FROM
        Posts p
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        RecentEdits re ON p.Id = re.PostId AND re.LatestEditRank = 1
    LEFT JOIN
        PostHistory ph ON re.PostId = ph.PostId AND re.UserId = ph.UserId AND re.CreationDate = ph.CreationDate
    WHERE
        p.PostTypeId IN (1, 2) AND p.CreationDate >= '2023-01-01'
)
SELECT
    pd.PostId,
    pd.Title,
    pd.Tags,
    pd.PostTypeName,
    pd.OwnerDisplayName,
    pd.Score,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.PostStatus,
    rc.AnswerRank AS GlobalAnswerRank,
    rc.AnswerScoreSum AS TotalAnswerScore,
    rc.QuestionCount AS UserTotalQuestions,
    rc.AnswerCount AS UserTotalAnswers,
    hr.Reputation AS HighReputation,
    ta.Score AS TopAnswerScoreForQuestion,
    ta.OwnerUserId AS TopAnswerOwnerId,
    re.LastEditComment AS LatestEditNote
FROM
    PostDetails pd
LEFT JOIN
    RankedUserContributions rc ON pd.OwnerUserId = rc.UserId
LEFT JOIN
    HighReputationUsers hr ON pd.OwnerUserId = hr.Id
LEFT JOIN
    TopAnswers ta ON pd.PostId = ta.QuestionId AND ta.AnswerOrderForQuestion = 1
LEFT JOIN
    RecentEdits re ON pd.PostId = re.PostId AND re.LatestEditRank = 1
WHERE
    pd.Score > 0
    AND pd.OwnerDisplayName IS NOT NULL
    AND (pd.AnswerCount IS NULL OR pd.AnswerCount > 5)
    AND EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.PostId = pd.PostId
        AND c.Score > 10
        AND UPPER(c.Text) LIKE '%PERFORMANCE%'
    )
UNION ALL
SELECT
    NULL,
    'Aggregated Metrics for Top Answerers',
    NULL,
    NULL,
    NULL,
    NULL,
    SUM(rc.AnswerCount),
    NULL,
    NULL,
    NULL,
    AVG(rc.AnswerRank),
    AVG(rc.AnswerScoreSum),
    AVG(rc.QuestionCount),
    AVG(rc.AnswerCount),
    AVG(hr.Reputation),
    NULL,
    NULL,
    NULL
FROM
    RankedUserContributions rc
LEFT JOIN
    HighReputationUsers hr ON rc.UserId = hr.Id
WHERE
    rc.AnswerRank <= 100;
