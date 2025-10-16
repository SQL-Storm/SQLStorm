WITH AnswerStats AS (
    SELECT 
        p.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        COALESCE(SUM(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END), 0) AS HighScoreAnswers,
        AVG(a.Score) AS AverageAnswerScore
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    GROUP BY p.Id
),
RecentComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(c.Text, ', ' ORDER BY c.CreationDate DESC) AS RecentCommentsText
    FROM Comments c
    WHERE c.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
    GROUP BY c.PostId
),
MostActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS ReputationRank
    FROM Users u
),
PostHistoryTypeCounts AS (
    SELECT
        pht.PostHistoryTypeId,
        COUNT(*) AS ChangeCount
    FROM PostHistory pht
    GROUP BY pht.PostHistoryTypeId
),
QuestionWithTags AS (
    SELECT
        p.Id,
        p.Title,
        -- normalize tags like "<tag1><tag2>" into "tag1, tag2"
        REPLACE(REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g'), '><', ', ') AS TagList,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.ViewCount,
        p.ClosedDate,
        p.LastActivityDate
    FROM Posts p
    LEFT JOIN AnswerStats a ON p.Id = a.QuestionId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > DATE '2023-01-01'
      AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate)
)
SELECT
    fp.Id AS QuestionId,
    fp.Title AS QuestionTitle,
    tp.TagList,
    u.DisplayName AS AskedBy,
    u.Reputation,
    u.Views AS UserViews,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(a.HighScoreAnswers, 0) AS HighScoreAnswers,
    a.AverageAnswerScore,
    COALESCE(c.CommentCount, 0) AS RecentCommentCount,
    c.RecentCommentsText,
    phtc.ChangeCount AS TotalRevisions,
    CASE WHEN fp.Score >= 10 THEN 'Popular' ELSE 'Average' END AS PopularityLabel,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, fp.ViewCount DESC) AS PedigreeRank
FROM FilteredPosts fp
LEFT JOIN Users u ON fp.OwnerUserId = u.Id
LEFT JOIN AnswerStats a ON fp.Id = a.QuestionId
LEFT JOIN RecentComments c ON fp.Id = c.PostId
LEFT JOIN PostHistoryTypeCounts phtc ON phtc.PostHistoryTypeId IN (4,5,6,7,8,10,12)
LEFT JOIN QuestionWithTags tp ON fp.Id = tp.Id
WHERE COALESCE(a.AnswerCount, 0) > 0
    AND fp.ViewCount > 100
    AND (fp.ClosedDate IS NULL OR fp.ClosedDate > fp.CreationDate)
GROUP BY
    fp.Id,
    fp.Title,
    tp.TagList,
    u.DisplayName,
    u.Reputation,
    u.Views,
    a.AnswerCount,
    a.HighScoreAnswers,
    a.AverageAnswerScore,
    c.CommentCount,
    c.RecentCommentsText,
    phtc.ChangeCount,
    fp.Score,
    fp.ViewCount,
    fp.CreationDate
ORDER BY fp.CreationDate DESC
LIMIT 10;