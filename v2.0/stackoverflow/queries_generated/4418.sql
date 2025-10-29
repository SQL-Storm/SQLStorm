-- {"query": "4418.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1505} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY OwnerUserId
),
UserReputation AS (
    SELECT
        Id,
        Reputation,
        DisplayName,
        Views AS UserViews,
        UpVotes AS UserUpVotes,
        DownVotes AS UserDownVotes,
        CreationDate AS UserCreationDate
    FROM Users
),
PostEngagement AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE NULL END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 ELSE NULL END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN 1 ELSE NULL END) AS TagEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes,
        MAX(CASE WHEN ph.PostHistoryTypeId = 19 THEN 1 ELSE 0 END) AS ProtectedStatus
    FROM PostHistory AS ph
    GROUP BY ph.PostId
),
AvgPostScores AS (
    SELECT
        pt.Name AS PostTypeName,
        AVG(p.Score) AS AverageScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    GROUP BY pt.Name
),
TopUsersWithPostDetails AS (
    SELECT
        ur.DisplayName,
        ur.Reputation,
        upc.TotalPosts,
        upc.QuestionCount,
        upc.AnswerCount,
        rp.PostId,
        rp.PostTypeName,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount AS PostAnswerCount,
        rp.CommentCount AS PostCommentCount,
        rp.FavoriteCount AS PostFavoriteCount,
        pe.BodyEdits,
        pe.TitleEdits,
        pe.TagEdits,
        pe.CloseVotes,
        pe.ReopenVotes,
        pe.ProtectedStatus,
        COALESCE(aps.AverageScore, 0) AS GlobalAverageScoreForType,
        CASE WHEN rp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM RankedPosts AS rp
    JOIN UserReputation AS ur ON rp.OwnerUserId = ur.Id
    JOIN UserPostCounts AS upc ON rp.OwnerUserId = upc.OwnerUserId
    LEFT JOIN PostEngagement AS pe ON rp.PostId = pe.PostId
    LEFT JOIN AvgPostScores AS aps ON rp.PostTypeName = aps.PostTypeName
    WHERE rp.rn <= 50 AND rp.Score > 10
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks
    FROM PostLinks AS pl
    JOIN LinkTypes AS lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    tupd.DisplayName,
    tupd.Reputation,
    tupd.TotalPosts,
    tupd.QuestionCount,
    tupd.AnswerCount,
    tupd.PostId,
    tupd.PostTypeName,
    tupd.Score,
    tupd.ViewCount,
    tupd.PostAnswerCount,
    tupd.PostCommentCount,
    tupd.PostFavoriteCount,
    tupd.BodyEdits,
    tupd.TitleEdits,
    tupd.TagEdits,
    tupd.CloseVotes,
    tupd.ReopenVotes,
    tupd.ProtectedStatus,
    tupd.GlobalAverageScoreForType,
    tupd.IsClosed,
    COALESCE(pls.LinkedPostsCount, 0) AS TotalRelatedPosts,
    COALESCE(pls.DuplicateLinks, 0) AS TotalDuplicateLinks,
    CASE
        WHEN tupd.Score > tupd.GlobalAverageScoreForType * 1.5 THEN 'High Performer'
        WHEN tupd.Score < tupd.GlobalAverageScoreForType * 0.5 THEN 'Low Performer'
        ELSE 'Average Performer'
    END AS PerformanceCategory,
    UPPER(SUBSTRING(tupd.DisplayName, 1, 3)) || '-' || LPAD(CAST(tupd.Reputation % 1000 AS VARCHAR), 3, '0') AS UserIdentifier,
    CASE
        WHEN tupd.PostTypeName = 'Question' AND tupd.PostFavoriteCount > 50 AND tupd.AnswerCount > 10 THEN 'Popular Question'
        WHEN tupd.PostTypeName = 'Answer' AND tupd.Score > 100 AND tupd.PostCommentCount > 5 THEN 'Highly Rated Answer'
        ELSE NULL
    END AS PostClassification
FROM TopUsersWithPostDetails AS tupd
LEFT JOIN PostLinkSummary AS pls ON tupd.PostId = pls.PostId
ORDER BY tupd.Reputation DESC, tupd.Score DESC
LIMIT 100;
