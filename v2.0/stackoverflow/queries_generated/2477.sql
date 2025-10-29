-- {"query": "2477.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1889} 

WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)) AS CloseReopenActions,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 0
), LatestUserActivity AS (
    SELECT * FROM RecursiveUserActivity WHERE rn = 1
), TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AnswerCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rank_per_user
    FROM Posts p
    WHERE p.PostTypeId = 1
), AnswerVotes AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        (COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) -
         COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0)) AS NetVotes
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId
), QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        MAX(av.NetVotes) FILTER (WHERE av.NetVotes IS NOT NULL) AS MaxAnswerNetVotes,
        AVG(av.NetVotes) FILTER (WHERE av.NetVotes IS NOT NULL) AS AvgAnswerNetVotes,
        SUM(av.UpVotes) AS TotalAnswerUpVotes,
        SUM(av.DownVotes) AS TotalAnswerDownVotes
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN AnswerVotes av ON av.AnswerId = a.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
), DuplicateLinkCounts AS (
    SELECT
        pl.PostId,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount
    FROM PostLinks pl
    GROUP BY pl.PostId
), UserBadgeRanks AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b
), LatestBadges AS (
    SELECT
        ub.UserId,
        STRING_AGG(ub.Name || ' (' || CASE ub.Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' ELSE 'Bronze' END || ')', ', ') AS RecentBadges
    FROM UserBadgeRanks ub
    WHERE ub.BadgeRank <= 5
    GROUP BY ub.UserId
), PostsWithClosingReason AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.ClosedDate,
        crt.Name AS CloseReasonName
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON crt.Id::varchar = ph.Comment -- Comment holds CloseReasonId as string
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
), TagSplit AS (
    SELECT
        q.Id AS QuestionId,
        unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) AS Tag
    FROM Posts q
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
), TagUsageCounts AS (
    SELECT
        ts.Tag,
        COUNT(DISTINCT ts.QuestionId) AS QuestionsWithTag,
        COUNT(DISTINCT p.OwnerUserId) AS DistinctUsersWithTaggedQuestions
    FROM TagSplit ts
    JOIN Posts p ON p.Id = ts.QuestionId
    GROUP BY ts.Tag
), UserQuestionTagStats AS (
    SELECT
        u.Id AS UserId,
        ts.Tag,
        COUNT(q.Id) AS QuestionCount,
        AVG(q.Score) AS AvgScore
    FROM Users u
    JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    JOIN TagSplit ts ON ts.QuestionId = q.Id
    GROUP BY u.Id, ts.Tag
), UsersWithActiveQuestions AS (
    SELECT u.UserId, u.DisplayName, cca.CloseReasonName, COUNT(*) AS ClosedQuestionsCount
    FROM LatestUserActivity u
    LEFT JOIN PostsWithClosingReason cca ON cca.PostId IN (
        SELECT q.Id FROM Posts q WHERE q.OwnerUserId = u.UserId AND q.PostTypeId = 1
    )
    GROUP BY u.UserId, u.DisplayName, cca.CloseReasonName
    HAVING COUNT(*) FILTER (WHERE cca.CloseReasonName IS NOT NULL) > 0
), UserActivitySummary AS (
    SELECT
        lua.UserId,
        lua.DisplayName,
        lua.Reputation,
        lua.QuestionCount,
        lua.AnswerCount,
        lua.BadgeCount,
        lua.CloseReopenActions,
        lb.RecentBadges,
        coalesce(dup.DuplicateCount,0) AS DuplicatesLinked,
        coalesce(dup.LinkedCount,0) AS TotalLinks,
        coalesce(qas.TotalAnswers,0) AS TotalAnswersToQuestions,
        coalesce(qas.MaxAnswerNetVotes,0) AS MaxAnswerNetVotes,
        coalesce(qas.AvgAnswerNetVotes,0) AS AvgAnswerNetVotes
    FROM LatestUserActivity lua
    LEFT JOIN LatestBadges lb ON lb.UserId = lua.UserId
    LEFT JOIN DuplicateLinkCounts dup ON dup.PostId IN (
        SELECT Id FROM Posts WHERE OwnerUserId = lua.UserId
    )
    LEFT JOIN QuestionAnswerStats qas ON qas.QuestionId IN (
        SELECT Id FROM Posts WHERE OwnerUserId = lua.UserId AND PostTypeId = 1
    )
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.BadgeCount,
    uas.CloseReopenActions,
    uas.RecentBadges,
    uas.DuplicatesLinked,
    uas.TotalLinks,
    uas.TotalAnswersToQuestions,
    uas.MaxAnswerNetVotes,
    uas.AvgAnswerNetVotes,
    array_agg(DISTINCT tucs.Tag ORDER BY tucs.QuestionsWithTag DESC) FILTER (WHERE tucs.Tag IS NOT NULL) AS PopularTagsUsed,
    EXISTS (
        SELECT 1 FROM UsersWithActiveQuestions uwaq WHERE uwaq.UserId = uas.UserId
    ) AS HasClosedQuestions,
    GREATEST(uas.Reputation, 0) - LEAST(uas.AnswerCount * 10, 100) +
        COALESCE(uas.AvgAnswerNetVotes * 5, 0) +
        COALESCE(uas.BadgeCount * 3, 0) AS ComplexUserScore
FROM UserActivitySummary uas
LEFT JOIN UserQuestionTagStats uqts ON uqts.UserId = uas.UserId
LEFT JOIN TagUsageCounts tucs ON tucs.Tag = uqts.Tag
WHERE uas.QuestionCount > 5
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.QuestionCount, uas.AnswerCount,
    uas.BadgeCount, uas.CloseReopenActions, uas.RecentBadges, uas.DuplicatesLinked,
    uas.TotalLinks, uas.TotalAnswersToQuestions, uas.MaxAnswerNetVotes, uas.AvgAnswerNetVotes
ORDER BY ComplexUserScore DESC
LIMIT 50;
