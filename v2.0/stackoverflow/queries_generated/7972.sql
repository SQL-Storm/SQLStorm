-- {"query": "7972.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1915} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Active'
            ELSE 'Beginner'
        END AS RepLevel,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'::timestamp
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 10 THEN 'High'
            WHEN p.Score > 5 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreLevel,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountFromCommentsTable,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS UpDownVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS FavoriteCount,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        NTILE(5) OVER (ORDER BY p.Score DESC) AS ScoreQuintile,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts) THEN 'AboveAvgScore'
            ELSE 'BelowAvgScore'
        END AS ScoreVsAvg,
        CASE 
            WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13,14,15)) THEN TRUE
            ELSE FALSE
        END AS HasHistoryAction
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'::timestamp 
    AND p.PostTypeId IN (1,2)
),
UserComplexAnalysis AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.AvgPostScore,
        us.LastPostDate,
        us.RepLevel,
        us.AllTags,
        (SELECT COUNT(*) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId AND pa.PostType = 'Question') AS QuestionCount,
        (SELECT COUNT(*) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId AND pa.PostType = 'Answer') AS AnswerCount,
        (SELECT SUM(pa.Score) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId AND pa.PostType = 'Question') AS TotalQuestionScore,
        (SELECT SUM(pa.Score) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId AND pa.PostType = 'Answer') AS TotalAnswerScore,
        (SELECT MAX(pa.Score) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId) AS MaxPostScore,
        (SELECT MIN(pa.Score) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId) AS MinPostScore,
        (SELECT AVG(pa.Score) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId AND pa.PostType = 'Question') AS AvgQuestionScore,
        (SELECT AVG(pa.Score) FROM PostAnalysis pa WHERE pa.OwnerUserId = us.UserId AND pa.PostType = 'Answer') AS AvgAnswerScore
    FROM UserStats us
    WHERE us.PostCount > 0
),
FinalAnalysis AS (
    SELECT 
        uca.UserId,
        uca.DisplayName,
        uca.Reputation,
        uca.PostCount,
        uca.CommentCount,
        uca.BadgeCount,
        uca.AvgPostScore,
        uca.LastPostDate,
        uca.RepLevel,
        uca.AllTags,
        uca.QuestionCount,
        uca.AnswerCount,
        uca.TotalQuestionScore,
        uca.TotalAnswerScore,
        uca.MaxPostScore,
        uca.MinPostScore,
        uca.AvgQuestionScore,
        uca.AvgAnswerScore,
        CASE WHEN uca.Reputation >= 10000 THEN 1 ELSE 0 END AS Has10kRep,
        CASE WHEN uca.BadgeCount >= 50 THEN 1 ELSE 0 END AS Has50Badges,
        (uca.Reputation * uca.PostCount) AS RepPostProduct,
        (uca.AvgPostScore * uca.QuestionCount) AS AvgScoreProd,
        CASE 
            WHEN uca.AvgQuestionScore > uca.AvgAnswerScore THEN 'QuestionFocussed'
            WHEN uca.AvgAnswerScore > uca.AvgQuestionScore THEN 'AnswerFocussed'
            ELSE 'Balanced'
        END AS PostingFocus
    FROM UserComplexAnalysis uca
    WHERE uca.Reputation BETWEEN 1000 AND 100000
)
SELECT 
    fa.*,
    COALESCE((
        SELECT TOP 1 ph.Comment 
        FROM PostHistory ph 
        WHERE ph.UserId = fa.UserId 
        AND ph.PostHistoryTypeId = 10
        ORDER BY ph.CreationDate DESC
    ), 'No Recent Closes') AS RecentCloseReason,
    COALESCE((
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId IN (
            SELECT p.Id FROM Posts p WHERE p.OwnerUserId = fa.UserId
        )
        AND pl.LinkTypeId = 3
    ), 0) AS DuplicateLinks,
    COALESCE((
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.UserId = fa.UserId 
        AND ph.PostHistoryTypeId IN (24, 25, 35)
        AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    ), 0) AS RecentEdits,
    CASE 
        WHEN fa.QuestionCount > 0 AND fa.AnswerCount = 0 THEN 'QuestionOnly'
        WHEN fa.AnswerCount > 0 AND fa.QuestionCount = 0 THEN 'AnswerOnly'
        WHEN fa.QuestionCount > 0 AND fa.AnswerCount > 0 THEN 'Both'
        ELSE 'Neither'
    END AS ContributionStyle,
    (fa.PostCount * 100.0 / (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = fa.UserId)) AS PostRatio,
    (SELECT COUNT(DISTINCT ParentId) FROM Posts WHERE OwnerUserId = fa.UserId AND PostTypeId = 2) AS UniqueAnsweredQuestions
FROM FinalAnalysis fa
WHERE fa.PostCount >= 5
AND (fa.QuestionCount > 0 OR fa.AnswerCount > 0)
AND fa.RepLevel IN ('Veteran', 'Elite')
ORDER BY fa.Reputation DESC, fa.PostCount DESC
LIMIT 1000
EXCEPT
SELECT 
    fa.*,
    'Excluded' AS RecentCloseReason,
    0 AS DuplicateLinks,
    0 AS RecentEdits,
    'Excluded' AS ContributionStyle,
    0.0 AS PostRatio,
    0 AS UniqueAnsweredQuestions
FROM FinalAnalysis fa
WHERE fa.RepLevel = 'Beginner'
AND fa.PostCount < 10
ORDER BY fa.Reputation ASC
LIMIT 500;