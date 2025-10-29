-- {"query": "4541.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1229}
WITH UserReputation AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS reputation_rank
    FROM Users
    WHERE Reputation > 1000
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        cr.Name AS CloseReason,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS INTEGER) AS AgeInDays,
        (p.ViewCount * 1.0 / NULLIF(p.AnswerCount, 0)) AS ViewsPerAnswer,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn,
        p.LastEditorUserId,
        p.LastEditDate,
        p.OwnerUserId
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN CloseReasonTypes cr ON cr.Id = (
        SELECT CAST(Comment AS INTEGER)
        FROM PostHistory
        WHERE PostHistoryTypeId = 10 AND PostId = p.Id
        ORDER BY CreationDate DESC
        LIMIT 1
    )
    WHERE p.PostTypeId IN (1, 2)
),
AggregatedVotes AS (
    SELECT
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
),
CommentActivity AS (
    SELECT
        PostId,
        COUNT(*) AS CommentCount,
        MAX(CreationDate) AS LastCommentDate
    FROM Comments
    GROUP BY PostId
),
PostAnalysis AS (
    SELECT
        pd.PostId,
        pd.Title,
        pd.PostTypeName,
        pd.OwnerDisplayName,
        pd.CreationDate,
        pd.Score,
        pd.AnswerCount,
        pd.CommentCount,
        pd.FavoriteCount,
        pd.IsClosed,
        pd.CloseReason,
        pd.AgeInDays,
        pd.ViewsPerAnswer,
        COALESCE(av.UpVotes, 0) AS TotalUpVotes,
        COALESCE(av.DownVotes, 0) AS TotalDownVotes,
        ca.CommentCount AS ActualCommentCount,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ca.LastCommentDate)) / 86400 AS INTEGER) AS DaysSinceLastComment,
        CASE
            WHEN pd.Score > 100 AND pd.AnswerCount > 10 THEN 'High Engagement'
            WHEN pd.Score < 0 AND pd.IsClosed = 1 THEN 'Low Quality Closed'
            WHEN pd.AgeInDays > 365 AND pd.AnswerCount = 0 THEN 'Old Unanswered'
            ELSE 'Standard'
        END AS PostStatusCategory,
        ud.DisplayName AS LastEditorDisplayName,
        pd.LastEditDate,
        pd.LastEditorUserId,
        pd.OwnerUserId,
        pd.rn
    FROM PostDetails pd
    LEFT JOIN AggregatedVotes av ON pd.PostId = av.PostId
    LEFT JOIN CommentActivity ca ON pd.PostId = ca.PostId
    LEFT JOIN Users ud ON pd.LastEditorUserId = ud.Id
    WHERE pd.rn = 1
)
SELECT
    pa.PostId,
    pa.Title,
    pa.PostTypeName,
    pa.OwnerDisplayName,
    pa.CreationDate,
    pa.Score,
    pa.AnswerCount,
    pa.CommentCount,
    pa.FavoriteCount,
    pa.IsClosed,
    pa.CloseReason,
    pa.AgeInDays,
    pa.ViewsPerAnswer,
    pa.TotalUpVotes,
    pa.TotalDownVotes,
    pa.ActualCommentCount,
    pa.DaysSinceLastComment,
    pa.PostStatusCategory,
    pa.LastEditorDisplayName,
    pa.LastEditDate,
    ur.DisplayName AS TopReputationUser,
    ur.Reputation AS TopReputation,
    ur.reputation_rank AS TopReputationRank,
    CASE
        WHEN pa.Score > ur.Reputation / 100 THEN 'Highly Scored Post'
        WHEN pa.DaysSinceLastComment > 30 AND pa.ActualCommentCount > 0 THEN 'Inactive Discussion'
        WHEN pa.ViewsPerAnswer IS NULL OR pa.ViewsPerAnswer < 1 THEN 'Low Interaction Ratio'
        ELSE 'Normal Activity'
    END AS PerformanceIndicator
FROM PostAnalysis pa
LEFT JOIN UserReputation ur ON pa.OwnerUserId = ur.UserId
WHERE pa.Score > -5
  AND pa.AgeInDays > 7
  AND pa.OwnerDisplayName IS NOT NULL
  AND pa.OwnerDisplayName <> 'Community'
  AND pa.TotalUpVotes > pa.TotalDownVotes
ORDER BY pa.Score DESC, pa.CreationDate ASC
LIMIT 100;