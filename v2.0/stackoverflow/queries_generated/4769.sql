-- {"query": "4769.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1407} 

WITH RECURSIVE TagHierarchy AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Id AS RootTagId,
        0 AS Level
    FROM Tags t
    WHERE t.TagName IN ('sql', 'performance', 'database', 'optimization', 'query')

    UNION ALL

    SELECT
        t.Id AS TagId,
        t.TagName,
        th.RootTagId,
        th.Level + 1 AS Level
    FROM Tags t
    JOIN Posts p ON SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) LIKE '%' || t.TagName || '%'
    JOIN TagHierarchy th ON th.TagId = t.Id
    WHERE th.Level < 3
),
PostTagCounts AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT th.RootTagId) AS RelevantTagCount,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS IsQuestion,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS IsClosed,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRankForType
    FROM Posts p
    LEFT JOIN TagHierarchy th ON SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) LIKE '%' || th.TagName || '%'
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    GROUP BY p.Id, p.PostTypeId, p.Score, p.CreationDate
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN c.UserId = u.Id THEN 1 ELSE 0 END) AS CommentCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 1000 AND u.Id != -1
    GROUP BY u.Id
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.ViewCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        CASE
            WHEN p.PostTypeId = 1 THEN COALESCE(p.Title, 'No Title')
            ELSE SUBSTRING(p.Body FROM 1 FOR 100)
        END AS Snippet
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate > '2023-01-01'
)
SELECT
    fp.Id AS PostId,
    fp.PostTypeName,
    fp.Snippet,
    fp.Score,
    fp.ViewCount,
    fp.FavoriteCount,
    fp.AnswerCount,
    fp.CommentCount,
    fp.CreationDate,
    fp.LastActivityDate,
    CASE WHEN fp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    upa.TotalPosts AS UserTotalPosts,
    upa.QuestionCount AS UserQuestionCount,
    upa.AnswerCount AS UserAnswerCount,
    upa.AvgQuestionScore AS UserAvgQuestionScore,
    upa.AvgAnswerScore AS UserAvgAnswerScore,
    upc.RelevantTagCount,
    upc.IsQuestion,
    upc.IsClosed,
    upc.AvgScoreForPostType,
    upc.PostRankForType,
    CASE
        WHEN u.DisplayName IS NULL THEN 'Anonymous'
        ELSE u.DisplayName
    END AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = fp.Id AND c.CreationDate > fp.CreationDate) AS CommentCountAfterPostCreation,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fp.Id AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fp.Id AND v.VoteTypeId = 3) AS DownVoteCount,
    CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = fp.Id AND pl.LinkTypeId = 3) THEN 'IsDuplicateOf' ELSE 'NotDuplicate' END AS DuplicateStatus,
    COALESCE(upa.LastPostDate, '1970-01-01') AS UserLastPostDate
FROM FilteredPosts fp
JOIN PostTagCounts upc ON fp.Id = upc.PostId
LEFT JOIN Users u ON fp.OwnerUserId = u.Id
LEFT JOIN UserPostActivity upa ON fp.OwnerUserId = upa.UserId
WHERE upc.RelevantTagCount > 1
  AND fp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = fp.PostTypeId) * 1.5
  AND LENGTH(fp.Snippet) > 50
  AND fp.CreationDate BETWEEN DATE_SUB(NOW(), INTERVAL 1 YEAR) AND NOW()
ORDER BY fp.LastActivityDate DESC
LIMIT 100;
