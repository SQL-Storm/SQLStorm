-- {"query": "4107.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1082} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.PostId) AS PostsEdited,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        COUNT(DISTINCT c.Id) AS CommentsMade
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Id <> -1
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionMetrics AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        ua.DisplayName AS OwnerDisplayName,
        ua.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.UserId IS NOT NULL) AS CommentCountOnQuestion,
        (SELECT SUM(Score) FROM Posts ans WHERE ans.ParentId = rp.PostId) AS TotalAnswerScore,
        CASE
            WHEN rp.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        DATEDIFF(day, rp.CreationDate, GETDATE()) AS DaysSinceCreation
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.PostTypeId = 1 AND rp.rn <= 500
),
TagPopularity AS (
    SELECT
        t.TagName,
        COUNT(pl.PostId) AS LinkCount,
        AVG(CAST(p.Score AS FLOAT)) AS AvgPostScoreForTag
    FROM Tags t
    JOIN PostLinks pl ON t.Id = pl.LinkTypeId
    JOIN Posts p ON pl.PostId = p.Id
    WHERE pl.LinkTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(pl.PostId) > 10
),
RecentHighScoringAnswers AS (
    SELECT
        p.ParentId AS QuestionId,
        p.Id AS AnswerId,
        p.Score AS AnswerScore,
        u.DisplayName AS AnswererDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2 AND p.CreationDate >= DATEADD(month, -6, GETDATE())
)
SELECT
    qm.PostId,
    qm.Title,
    qm.CreationDate,
    qm.Score,
    qm.ViewCount,
    qm.OwnerDisplayName,
    qm.OwnerReputation,
    qm.CommentCountOnQuestion,
    qm.TotalAnswerScore,
    qm.HasAcceptedAnswer,
    qm.DaysSinceCreation,
    COALESCE(tp.LinkCount, 0) AS RelatedPostLinkCount,
    COALESCE(tp.AvgPostScoreForTag, 0) AS AvgTagPostScore,
    CASE
        WHEN qm.Score > 100 THEN 'High'
        WHEN qm.Score > 10 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreCategory,
    rhsa.AnswerScore AS TopAnswerScore,
    rhsa.AnswererDisplayName AS TopAnswererDisplayName
FROM QuestionMetrics qm
LEFT JOIN TagPopularity tp ON qm.Title LIKE '%' + tp.TagName + '%' -- Simple tag matching for demonstration
LEFT JOIN RecentHighScoringAnswers rhsa ON qm.PostId = rhsa.QuestionId AND rhsa.AnswerRank = 1
WHERE qm.OwnerReputation > 1000
UNION ALL
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
WHERE EXISTS (SELECT 1 FROM Users WHERE Reputation < 100);