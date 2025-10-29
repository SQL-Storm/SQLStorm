-- {"query": "4035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1190}
WITH RelevantPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        CASE
            WHEN p.Title IS NOT NULL THEN LEFT(p.Title, 50)
            ELSE 'No Title'
        END AS TruncatedTitle,
        COALESCE(u.DisplayName, p.OwnerDisplayName) AS PostOwnerDisplayName,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    GROUP BY c.PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS UserPostCount,
        SUM(p.Score) AS UserTotalScore,
        AVG(p.Score) AS UserAvgScore,
        MAX(p.CreationDate) AS UserLastPostDate
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
PostVoteAnalysis AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVoteCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 WHEN vt.Name = 'DownMod' THEN -1 ELSE 0 END) AS NetVoteScore
    FROM Votes AS v
    JOIN VoteTypes AS vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod')
    GROUP BY v.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.TruncatedTitle,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    COALESCE(pc.CommentCount, 0) AS ActualCommentCount,
    COALESCE(pc.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(pc.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(pva.UpVoteCount, 0) AS UpVotes,
    COALESCE(pva.DownVoteCount, 0) AS DownVotes,
    COALESCE(pva.NetVoteScore, 0) AS NetVotes,
    COALESCE(upa.UserPostCount, 0) AS OwnerPostCount,
    COALESCE(upa.UserTotalScore, 0) AS OwnerTotalScore,
    COALESCE(upa.UserAvgScore, 0) AS OwnerAvgScore,
    rp.PostOwnerDisplayName,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.PostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY) THEN 'Recent'
        ELSE 'Older'
    END AS PostStatusCategory,
    COALESCE(rp.FavoriteCount, 0) AS FavoriteCount,
    rp.rn AS RowNumber,
    CAST(rp.PostCreationDate AS DATE) AS PostDateOnly,
    UPPER(SUBSTRING(rp.PostOwnerDisplayName FROM 1 FOR 3)) AS OwnerDisplayNamePrefix,
    CASE
        WHEN rp.PostScore > 100 THEN 'High'
        WHEN rp.PostScore < 0 THEN 'Negative'
        ELSE 'NeutralOrPositive'
    END AS ScoreCategory,
    CASE
        WHEN pc.LastCommentDate IS NOT NULL AND pc.LastCommentDate > rp.PostCreationDate THEN 'HasCommentsAfterCreation'
        ELSE 'NoCommentsAfterCreation'
    END AS CommentTiming,
    COALESCE(CHAR_LENGTH(rp.TruncatedTitle), 0) AS TitleLength,
    rp.PostTypeId,
    rp.OwnerUserId
FROM RelevantPosts AS rp
LEFT JOIN PostComments AS pc ON rp.PostId = pc.PostId
LEFT JOIN PostVoteAnalysis AS pva ON rp.PostId = pva.PostId
LEFT JOIN UserPostActivity AS upa ON rp.OwnerUserId = upa.OwnerUserId
WHERE rp.PostCreationDate BETWEEN CAST('2023-01-01' AS DATE) AND CAST('2023-12-31' AS DATE)
  AND rp.PostScore > -5
  AND rp.PostOwnerDisplayName ILIKE '%test%'
GROUP BY
    rp.PostId,
    rp.PostTypeName,
    rp.TruncatedTitle,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    pc.CommentCount,
    pc.TotalCommentScore,
    pc.AvgCommentScore,
    pva.UpVoteCount,
    pva.DownVoteCount,
    pva.NetVoteScore,
    upa.UserPostCount,
    upa.UserTotalScore,
    upa.UserAvgScore,
    rp.PostOwnerDisplayName,
    rp.ClosedDate,
    rp.FavoriteCount,
    rp.rn,
    rp.PostCreationDate,
    rp.PostOwnerDisplayName,
    rp.PostScore,
    pc.LastCommentDate,
    rp.TruncatedTitle,
    rp.PostTypeId,
    rp.OwnerUserId
ORDER BY rp.PostCreationDate DESC
LIMIT 1000;