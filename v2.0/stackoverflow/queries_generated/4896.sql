-- {"query": "4896.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1042} 
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS DistinctPostsEdited,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN 1 ELSE 0 END) AS Edits,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) OVER (PARTITION BY u.Id) AS AvgAnswerCountForQuestions,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS ReputationRank
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Posts p ON ph.PostId = p.Id
    WHERE u.DisplayName IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostInteraction AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.Score,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount > 100 THEN 'High Answer Count'
            ELSE 'Standard'
        END AS PostStatusCategory,
        COUNT(DISTINCT c.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) as ActivitySequence
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.Score > 0 OR p.CommentCount > 0
    GROUP BY p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, u.DisplayName, p.Score, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CreationDate, p.AnswerCount
)
SELECT
    r.DisplayName AS UserDisplayName,
    r.Reputation,
    r.ReputationRank,
    r.UserCreationDate,
    r.DistinctPostsEdited,
    r.Edits,
    r.AvgAnswerCountForQuestions,
    pi.PostId,
    pi.PostTypeName,
    pi.Score,
    pi.CommentCountForPost,
    pi.UpVoteCount,
    pi.DownVoteCount,
    pi.PostStatusCategory,
    (pi.UpVoteCount - pi.DownVoteCount) AS NetVoteScore,
    CASE
        WHEN pi.OwnerDisplayName IS NULL THEN 'Community'
        WHEN pi.OwnerDisplayName = r.DisplayName THEN 'Self'
        ELSE 'Other'
    END AS OwnerRelationship,
    COALESCE(
        CASE
            WHEN pi.PostTypeId = 1 AND pi.ClosedDate IS NOT NULL THEN (SELECT Name FROM CloseReasonTypes WHERE Id = (SELECT CAST(Comment AS INT) FROM PostHistory WHERE PostId = pi.PostId AND PostHistoryTypeId = 10 ORDER BY CreationDate DESC LIMIT 1))
            ELSE NULL
        END,
        'Not Closed or Reason Unknown'
    ) AS CloseReason,
    pht.Name AS LastEditType,
    COALESCE(LENGTH(pi.OwnerDisplayName), 0) AS OwnerDisplayNameLength,
    SUBSTRING(pi.PostTypeName, 1, 3) AS PostTypeAbbreviation
FROM RankedUserActivity r
JOIN PostInteraction pi ON r.UserId = pi.OwnerUserId
LEFT JOIN PostHistory ph_last ON pi.PostId = ph_last.PostId AND ph_last.ActivitySequence = 1
LEFT JOIN PostHistoryTypes pht ON ph_last.PostHistoryTypeId = pht.Id
WHERE r.Reputation > 1000
  AND pi.Score > 5
  AND pi.CommentCountForPost > 2
  AND pi.PostTypeName IN ('Question', 'Answer')
ORDER BY r.Reputation DESC, pi.Score DESC, pi.PostId
LIMIT 100;