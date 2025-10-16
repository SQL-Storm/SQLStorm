-- {"query": "907.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1705} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(p.Score, 0) AS TagScore,
        1 AS Level,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.IsModeratorOnly = 0
    UNION ALL
    SELECT
        th.Id,
        th.TagName,
        th.TagScore,
        th.Level + 1,
        th.TagPath || t2.TagName
    FROM RecursiveTagHierarchy th
    JOIN Tags t2 ON t2.Id <> th.Id
    WHERE NOT t2.TagName = ANY(th.TagPath)
      AND th.Level < 3
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(COALESCE(vtCount.UpVotes,0)) AS UpVotesReceived,
        SUM(COALESCE(vtCount.DownVotes,0)) AS DownVotesReceived,
        MAX(p.CreationDate) AS LastPostDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ) vtCount ON vtCount.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.CreationDate AS QuestionCreationDate,
        ua.UserId,
        ua.DisplayName AS UserName,
        ua.ReputationRank,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerCommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS AnswerUpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3) AS AnswerDownVotes,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank
    FROM Posts q
    LEFT JOIN Users ua ON ua.Id = q.OwnerUserId
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
TopAnswersWithLinks AS (
    SELECT
        qas.*,
        pl.LinkTypeId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM QuestionAnswerStats qas
    LEFT JOIN PostLinks pl ON pl.PostId = qas.AnswerId
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE qas.AnswerRank = 1
),
FilteredBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RecentBadgeRank
    FROM Badges b
    WHERE b.Class IN (1,2) -- Gold or Silver badges
),
FinalResult AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.ReputationRank,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        qas.QuestionId,
        qas.Title AS QuestionTitle,
        qas.Tags,
        qas.QuestionScore,
        qas.ViewCount,
        qas.QuestionCreationDate,
        qas.AnswerId,
        qas.AnswerScore,
        qas.AnswerCreationDate,
        qas.AnswerCommentCount,
        qas.AnswerUpVotes,
        qas.AnswerDownVotes,
        tal.LinkTypeName,
        fb.BadgeName,
        fb.BadgeClass,
        COUNT(DISTINCT th.Id) FILTER (WHERE th.Level = 1) AS DirectTagCount,
        COUNT(DISTINCT th.Id) FILTER (WHERE th.Level > 1) AS RelatedTagCount,
        STRING_AGG(DISTINCT th.TagName, ',' ORDER BY th.TagName) AS AllRelatedTags
    FROM UserActivity ua
    LEFT JOIN QuestionAnswerStats qas ON qas.UserId = ua.UserId
    LEFT JOIN TopAnswersWithLinks tal ON tal.AnswerId = qas.AnswerId
    LEFT JOIN FilteredBadges fb ON fb.UserId = ua.UserId AND fb.RecentBadgeRank = 1
    LEFT JOIN RecursiveTagHierarchy th ON th.TagName = ANY(string_to_array(replace(qas.Tags,'><',','), ','))
    WHERE ua.ReputationRank <= 1000
    GROUP BY
        ua.UserId, ua.DisplayName, ua.ReputationRank, ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade,
        ua.UpVotesReceived, ua.DownVotesReceived,
        qas.QuestionId, qas.Title, qas.Tags, qas.QuestionScore, qas.ViewCount, qas.QuestionCreationDate,
        qas.AnswerId, qas.AnswerScore, qas.AnswerCreationDate, qas.AnswerCommentCount, qas.AnswerUpVotes, qas.AnswerDownVotes,
        tal.LinkTypeName, fb.BadgeName, fb.BadgeClass
)
SELECT
    fr.UserId,
    fr.DisplayName,
    fr.ReputationRank,
    fr.QuestionsPosted,
    fr.AnswersPosted,
    fr.CommentsMade,
    fr.UpVotesReceived,
    fr.DownVotesReceived,
    fr.QuestionId,
    LEFT(fr.QuestionTitle, 100) || CASE WHEN LENGTH(fr.QuestionTitle) > 100 THEN '...' ELSE '' END AS TruncatedQuestionTitle,
    fr.Tags,
    fr.QuestionScore,
    fr.ViewCount,
    fr.QuestionCreationDate,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerCreationDate,
    fr.AnswerCommentCount,
    fr.AnswerUpVotes,
    fr.AnswerDownVotes,
    COALESCE(fr.LinkTypeName, 'No Link') AS LinkTypeName,
    COALESCE(fr.BadgeName, 'No Recent Gold/Silver Badge') AS RecentBadgeName,
    fr.BadgeClass,
    fr.DirectTagCount,
    fr.RelatedTagCount,
    fr.AllRelatedTags,
    CASE
        WHEN fr.AnswerScore > 10 AND fr.QuestionScore > 5 THEN 'High Impact'
        WHEN fr.AnswerScore BETWEEN 5 AND 10 OR fr.QuestionScore BETWEEN 3 AND 5 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS ImpactLevel,
    CASE
        WHEN fr.AnswerCreationDate < fr.QuestionCreationDate + INTERVAL '1 day' THEN 'Fast Answer'
        ELSE 'Slow Answer'
    END AS AnswerSpeedCategory
FROM FinalResult fr
WHERE fr.AnswerId IS NOT NULL
ORDER BY fr.ReputationRank, fr.QuestionScore DESC, fr.AnswerScore DESC
LIMIT 100;
