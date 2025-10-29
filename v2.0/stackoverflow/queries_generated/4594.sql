-- {"query": "4594.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 986} 

WITH RankedUserVotes AS (
    SELECT
        v.UserId,
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) as rn
    FROM Votes v
    INNER JOIN Users u ON v.UserId = u.Id
    WHERE u.Reputation > 10000
),
PostVoteCounts AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
),
RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.AnswerCount,
        p.Score,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn_questions
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-30 days')
),
TopAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_answers
    FROM Posts p
    WHERE p.PostTypeId = 2
),
UserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS PostEditCount,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Id IN (SELECT UserId FROM RankedUserVotes WHERE rn <= 5)
    GROUP BY u.Id, u.DisplayName
)
SELECT
    rq.QuestionId,
    rq.Title AS QuestionTitle,
    COALESCE(u.DisplayName, 'Anonymous') AS QuestionOwnerDisplayName,
    rq.QuestionCreationDate,
    rq.Score AS QuestionScore,
    rq.AnswerCount AS QuestionAnswerCount,
    pvc.UpVoteCount AS QuestionUpVotes,
    pvc.DownVoteCount AS QuestionDownVotes,
    pvc.FavoriteCount AS QuestionFavoriteCount,
    ta.AnswerId AS TopAnswerId,
    ta.Score AS TopAnswerScore,
    COALESCE(ta_owner.DisplayName, 'Anonymous') AS TopAnswerOwnerDisplayName,
    ta.AnswerCreationDate,
    uc.BadgeCount,
    uc.PostEditCount,
    uc.CommentCount,
    CASE
        WHEN rq.QuestionCreationDate < DATE('now', '-1 year') AND rq.AnswerCount = 0 THEN 'Old unanswered question'
        WHEN pvc.UpVoteCount > pvc.DownVoteCount * 2 AND pvc.FavoriteCount > 10 THEN 'Popular question'
        WHEN rq.Score < 0 THEN 'Negatively scored question'
        ELSE 'Standard question'
    END AS QuestionStatus
FROM RecentQuestions rq
LEFT JOIN Users u ON rq.OwnerUserId = u.Id
LEFT JOIN PostVoteCounts pvc ON rq.QuestionId = pvc.PostId
LEFT JOIN TopAnswers ta ON rq.QuestionId = ta.QuestionId AND ta.rn_answers = 1
LEFT JOIN Users ta_owner ON ta.OwnerUserId = ta_owner.Id
LEFT JOIN UserContributions uc ON rq.OwnerUserId = uc.UserId
WHERE rq.rn_questions <= 50
ORDER BY rq.QuestionCreationDate DESC, rq.Score DESC
LIMIT 100;
