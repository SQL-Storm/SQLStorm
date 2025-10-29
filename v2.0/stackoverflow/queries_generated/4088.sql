-- {"query": "4088.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1306} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.ViewCount, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS NextViewCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 END) AS CloseEvents,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 10, 101, 102, 103, 104, 105)
    GROUP BY ph.PostId
),
CommentActivity AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
UserPostContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScoreOfPosts,
        AVG(p.ViewCount) AS AvgPostViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 5 -- Users with at least 6 posts
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount AS DirectAnswerCount,
    COALESCE(ca.CommentCountForPost, 0) AS TotalComments,
    COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(phs.TitleEdits, 0) AS TitleEditCount,
    COALESCE(phs.BodyEdits, 0) AS BodyEditCount,
    phs.LastCloseDate,
    rp.RankByScoreView,
    rp.PreviousScore,
    rp.NextViewCount,
    upc.QuestionCount AS UserQuestions,
    upc.AnswerCount AS UserAnswers,
    upc.TotalScoreOfPosts AS UserTotalScore,
    upc.AvgPostViewCount AS UserAvgViewCount,
    CASE
        WHEN rp.ClosedDate IS NOT NULL AND rp.CommunityOwnedDate IS NULL THEN 'Open & Not Community Owned'
        WHEN rp.ClosedDate IS NULL AND rp.CommunityOwnedDate IS NOT NULL THEN 'Closed & Community Owned'
        WHEN rp.ClosedDate IS NOT NULL AND rp.CommunityOwnedDate IS NOT NULL THEN 'Closed & Community Owned'
        ELSE 'Open & Not Community Owned'
    END AS PostStatus,
    UPPER(SUBSTRING(rp.OwnerDisplayName FROM 1 FOR 1)) || LOWER(SUBSTRING(rp.OwnerDisplayName FROM 2)) AS FormattedDisplayName, -- Basic display name formatting
    rp.Score + COALESCE(ca.TotalCommentScore, 0) AS CombinedScore,
    CASE
        WHEN rp.Score > 500 AND rp.ViewCount > 10000 THEN 'High Value Post'
        WHEN rp.Score < 0 THEN 'Negative Score Post'
        ELSE 'Standard Post'
    END AS PostValueCategory,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Is Duplicate Of'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Has Duplicates'
        ELSE 'No Duplicate Link'
    END AS DuplicateStatus
FROM RankedPosts rp
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN CommentActivity ca ON rp.PostId = ca.PostId
LEFT JOIN UserPostContribution upc ON rp.OwnerUserId = upc.UserId
WHERE rp.PostTypeId = 1 -- Further filter to only show questions for the final output
ORDER BY rp.RankByScoreView;
