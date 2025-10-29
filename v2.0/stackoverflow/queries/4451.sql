-- {"query": "4451.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1018}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentComments AS (
    SELECT
        c.PostId,
        c.UserId AS CommenterUserId,
        c.CreationDate AS CommentCreationDate,
        c.Score AS CommentScore,
        COUNT(c.Id) OVER(PARTITION BY c.PostId) AS CommentCountForPost,
        ROW_NUMBER() OVER(PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS LatestCommentRn
    FROM Comments c
    WHERE c.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days')
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        COALESCE(rc.CommentCountForPost, 0) AS NumberOfRecentComments,
        COALESCE(v.UpVoteCount, 0) AS UpVoteCount,
        COALESCE(v.DownVoteCount, 0) AS DownVoteCount,
        COALESCE(v.FavoriteCount, 0) AS FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
            SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN RecentComments rc ON p.Id = rc.PostId AND rc.LatestCommentRn = 1
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days')
)
SELECT
    rp.PostId,
    rp.Title AS PostTitle,
    rp.PostTypeName,
    rp.PostCreationDate,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(upc.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(upc.QuestionCount, 0) AS UserQuestionCount,
    COALESCE(upc.AnswerCount, 0) AS UserAnswerCount,
    upc.AverageScore AS UserAveragePostScore,
    pe.NumberOfRecentComments,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.FavoriteCount,
    pe.IsClosed,
    CASE
        WHEN pe.UpVoteCount > pe.DownVoteCount * 2 AND pe.NumberOfRecentComments < 5 THEN 'Potentially Viral'
        WHEN pe.FavoriteCount > 10 AND pe.IsClosed = 0 THEN 'Highly Faved'
        WHEN upc.AverageScore > 50 THEN 'Expert User Post'
        ELSE 'Standard Post'
    END AS PostStatusCategory,
    UPPER(SUBSTRING(rp.Title FROM 1 FOR 3)) || '-' || LOWER(rp.PostTypeName) AS TitlePrefixType
FROM RankedPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostCounts upc ON rp.OwnerUserId = upc.OwnerUserId
LEFT JOIN PostEngagement pe ON rp.PostId = pe.PostId
WHERE rp.rn <= 1000
ORDER BY rp.PostCreationDate DESC;