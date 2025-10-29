-- {"query": "2717.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1636} 
WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COALESCE(array_agg(DISTINCT p.Id) FILTER (WHERE p.Id IS NOT NULL), ARRAY[]::int[]) AS PostIds,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    GROUP BY t.Id, t.TagName

    UNION ALL

    SELECT
        th.Id,
        th.TagName,
        rh.PostIds || COALESCE(array_agg(DISTINCT p.Id) FILTER (WHERE p.Id IS NOT NULL), ARRAY[]::int[]),
        Level + 1
    FROM RecursiveTagHierarchy th
    JOIN PostLinks pl ON pl.PostId = ANY(th.PostIds)
    JOIN Posts p ON p.Id = pl.RelatedPostId
    JOIN RecursiveTagHierarchy rh ON rh.Id = th.Id
    WHERE pl.LinkTypeId = 1 AND Level < 3
    GROUP BY th.Id, th.TagName, Level, rh.PostIds
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(COALESCE(vt_up.VotesCount, 0)) OVER (PARTITION BY u.Id ORDER BY u.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS TotalUpVotes,
        SUM(COALESCE(vt_down.VotesCount, 0)) OVER (PARTITION BY u.Id ORDER BY u.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS TotalDownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VotesCount, PostOwnerId FROM (
            SELECT v.PostId, p.OwnerUserId AS PostOwnerId
            FROM Votes v
            JOIN Posts p ON p.Id = v.PostId
            WHERE v.VoteTypeId = 2
        ) uv
        GROUP BY PostId, PostOwnerId
    ) vt_up ON vt_up.PostOwnerId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VotesCount, PostOwnerId FROM (
            SELECT v.PostId, p.OwnerUserId AS PostOwnerId
            FROM Votes v
            JOIN Posts p ON p.Id = v.PostId
            WHERE v.VoteTypeId = 3
        ) dv
        GROUP BY PostId, PostOwnerId
    ) vt_down ON vt_down.PostOwnerId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, vt_up.VotesCount, vt_down.VotesCount
),
AnswerScoreAnalysis AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerUserId,
        a.Score AS AnswerScore,
        q.Score AS QuestionScore,
        q.Title,
        COUNT(pl.Id) AS LinkedCount,
        STRING_AGG(DISTINCT lt.Name, ', ') AS LinkTypes,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        EXISTS (
            SELECT 1 FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 1
        ) AS IsAcceptedAnswer
    FROM Posts a
    LEFT JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    LEFT JOIN PostLinks pl ON pl.PostId = a.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, q.Score, q.Title, a.CreationDate
),
ComplexCloseReasonCounts AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 AND (ph.Comment::int = 101 OR ph.Comment::int = 1) THEN 1 END) AS DuplicateCloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 AND (ph.Comment::int = 102 OR ph.Comment::int = 2) THEN 1 END) AS OffTopicCloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 AND (ph.Comment::int = 103 OR ph.Comment::int = 3) THEN 1 END) AS NeedsDetailsCloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 AND (ph.Comment::int = 104 OR ph.Comment::int = 4) THEN 1 END) AS NeedsMoreFocusCloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 AND (ph.Comment::int = 105 OR ph.Comment::int = 5) THEN 1 END) AS OpinionBasedCloseVotes
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
FinalSelection AS (
    SELECT
        uaw.UserId,
        uaw.DisplayName,
        uaw.Reputation,
        uaw.QuestionCount,
        uaw.AnswerCount,
        uaw.CommentCount,
        uaw.TotalUpVotes,
        uaw.TotalDownVotes,
        asa.AnswerId,
        asa.QuestionId,
        asa.AnswerScore,
        asa.QuestionScore,
        CONCAT(LEFT(asa.Title, 50), CASE WHEN LENGTH(asa.Title) > 50 THEN '...' ELSE '' END) AS ShortQuestionTitle,
        asa.LinkedCount,
        COALESCE(asa.LinkTypes, 'None') AS LinkTypes,
        asa.AnswerRank,
        asa.IsAcceptedAnswer,
        crc.DuplicateCloseVotes,
        crc.OffTopicCloseVotes,
        crc.NeedsDetailsCloseVotes,
        crc.NeedsMoreFocusCloseVotes,
        crc.OpinionBasedCloseVotes,
        ROW_NUMBER() OVER (PARTITION BY uaw.UserId ORDER BY asa.AnswerScore DESC NULLS LAST) AS AnswerRankPerUser
    FROM UserActivityWindow uaw
    LEFT JOIN AnswerScoreAnalysis asa ON asa.AnswerUserId = uaw.UserId
    LEFT JOIN ComplexCloseReasonCounts crc ON crc.PostId = asa.QuestionId
    WHERE uaw.Reputation > 1000 OR uaw.TotalUpVotes > 50
)
SELECT
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.QuestionCount,
    fs.AnswerCount,
    fs.CommentCount,
    fs.TotalUpVotes,
    fs.TotalDownVotes,
    fs.AnswerId,
    fs.QuestionId,
    fs.AnswerScore,
    fs.QuestionScore,
    fs.ShortQuestionTitle,
    fs.LinkedCount,
    fs.LinkTypes,
    fs.AnswerRank,
    fs.IsAcceptedAnswer,
    fs.DuplicateCloseVotes,
    fs.OffTopicCloseVotes,
    fs.NeedsDetailsCloseVotes,
    fs.NeedsMoreFocusCloseVotes,
    fs.OpinionBasedCloseVotes
FROM FinalSelection fs
WHERE fs.AnswerRankPerUser <= 3
ORDER BY fs.Reputation DESC NULLS LAST, fs.AnswerScore DESC NULLS LAST, fs.UserId, fs.AnswerRankPerUser;