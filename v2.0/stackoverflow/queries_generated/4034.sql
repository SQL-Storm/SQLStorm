-- {"query": "4034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1295} 
WITH QuestionEdits AS (
    SELECT
        p.Id AS QuestionId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 6) THEN 1 ELSE NULL END) AS TitleOrTagEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE NULL END) AS BodyEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysSinceLastActivity,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId AND p.PostTypeId = 1
    WHERE
        p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.CreationDate > '2023-01-01'
    GROUP BY
        p.Id, p.CreationDate, p.LastActivityDate, p.ClosedDate
),
TopUsersByReputation AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM
        Users
    WHERE
        CreationDate < '2023-01-01'
),
AveragePostScore AS (
    SELECT
        OwnerUserId,
        AVG(CAST(Score AS FLOAT)) AS AvgScore,
        COUNT(Id) AS NumPosts
    FROM
        Posts
    WHERE
        PostTypeId = 2 AND OwnerUserId IS NOT NULL
    GROUP BY
        OwnerUserId
    HAVING
        COUNT(Id) > 10
),
PostsWithComments AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        AVG(CAST(c.Score AS FLOAT)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.Id, p.Title, p.OwnerUserId
    HAVING
        COUNT(c.Id) > 5
)
SELECT
    qe.QuestionId,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    qe.TitleOrTagEdits,
    qe.BodyEdits,
    qe.DaysSinceLastActivity,
    qe.IsClosed,
    CASE
        WHEN p.FavoriteCount IS NULL THEN 0
        ELSE p.FavoriteCount
    END AS ActualFavoriteCount,
    CASE
        WHEN ps.AvgScore IS NULL THEN 0.0
        ELSE ps.AvgScore
    END AS AverageAnswerScore,
    CASE
        WHEN psc.CommentCount > 0 THEN psc.CommentCount
        ELSE 0
    END AS NumberOfComments,
    CASE
        WHEN psc.AvgCommentScore IS NOT NULL THEN psc.AvgCommentScore
        ELSE 0.0
    END AS AverageCommentSentimentScore,
    CASE
        WHEN tur.ReputationRank <= 100 THEN 'Top 100 User'
        WHEN tur.ReputationRank <= 500 THEN 'Top 500 User'
        ELSE 'Other User'
    END AS UserTier,
    CASE
        WHEN INSTR(p.Tags, '<sql>') > 0 THEN 'SQL Related'
        WHEN INSTR(p.Tags, '<performance>') > 0 THEN 'Performance Related'
        ELSE 'Other Tag'
    END AS TagCategory,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    p.CreationDate AS QuestionCreationDate,
    p.LastActivityDate AS QuestionLastActivityDate
FROM
    QuestionEdits qe
JOIN
    Posts p ON qe.QuestionId = p.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    AveragePostScore ps ON p.OwnerUserId = ps.OwnerUserId
LEFT JOIN
    PostsWithComments psc ON qe.QuestionId = psc.PostId
LEFT JOIN
    TopUsersByReputation tur ON u.Id = tur.Id
WHERE
    qe.DaysSinceLastActivity > 30
    AND qe.TitleOrTagEdits > 0
    AND p.Score > 5
    AND (p.AnswerCount IS NULL OR p.AnswerCount < 10)
    AND u.DownVotes < u.UpVotes * 2
UNION
SELECT
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM
    PostLinks pl
WHERE
    pl.LinkTypeId = 3 AND pl.CreationDate < '2023-01-01'
GROUP BY
    pl.PostId, pl.RelatedPostId
HAVING
    COUNT(pl.Id) > 5;