-- {"query": "4431.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1037}
WITH RankedQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.CreationDate) AS LastQuestionDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
),
QuestionDetails AS (
    SELECT
        rq.PostId,
        rq.Title,
        rq.OwnerUserId,
        rq.OwnerDisplayName,
        rq.PostCreationDate,
        ua.QuestionCount,
        ua.CommentCount,
        ua.UpVoteCount,
        ua.DownVoteCount,
        ua.LastQuestionDate
    FROM RankedQuestions rq
    LEFT JOIN UserActivity ua ON rq.OwnerUserId = ua.UserId
    WHERE rq.rn <= 5
),
PostInteraction AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT pl.Id) AS LinkCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.ClosedDate
)
SELECT
    qd.Title,
    qd.OwnerDisplayName,
    qd.PostCreationDate,
    qd.QuestionCount AS UserTotalQuestions,
    qd.CommentCount AS UserTotalComments,
    qd.UpVoteCount AS UserTotalUpVotes,
    qd.DownVoteCount AS UserTotalDownVotes,
    qd.LastQuestionDate AS UserLastQuestion,
    pi.CommentCount AS PostCommentCount,
    pi.LinkCount AS PostLinkCount,
    pi.UpVoteCount AS PostUpVotes,
    pi.DownVoteCount AS PostDownVotes,
    CASE WHEN pi.IsClosed = 1 THEN 'Closed' ELSE 'Open' END AS PostStatus,
    DENSE_RANK() OVER (ORDER BY qd.QuestionCount DESC, qd.PostCreationDate DESC) AS UserQuestionRank,
    LAG(qd.OwnerDisplayName, 1, 'N/A') OVER (ORDER BY qd.PostCreationDate) AS PreviousQuestioner,
    COALESCE(pht.Comment, 'No Revision Comment') AS LastRevisionComment,
    CASE
        WHEN CHAR_LENGTH(qd.OwnerDisplayName) > 10 THEN UPPER(SUBSTRING(qd.OwnerDisplayName FROM 1 FOR 10)) || '...'
        ELSE qd.OwnerDisplayName
    END AS TruncatedOwnerName
FROM QuestionDetails qd
LEFT JOIN PostInteraction pi ON qd.PostId = pi.PostId
LEFT JOIN (
    SELECT
        ph.PostId,
        ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
) pht ON qd.PostId = pht.PostId AND pht.rn = 1
WHERE qd.PostCreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
ORDER BY qd.PostCreationDate DESC
LIMIT 100;