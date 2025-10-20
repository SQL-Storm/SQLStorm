-- {"query": "4078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2474} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(t.Count, 0) AS TagCount,
        1 AS Level,
        ARRAY[t.TagName] AS Ancestry
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        COALESCE(child.Count, 0),
        parent.Level + 1,
        parent.Ancestry || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.Id <> parent.Id
    WHERE array_position(parent.Ancestry, child.TagName) IS NULL -- prevent cycles
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(b.Id) AS TotalBadges,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId IN (10, 11)) AS ClosedOrReopenedPosts,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostWithVotesAndLinks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        vUp.CountUpVotes,
        vDown.CountDownVotes,
        COALESCE(plLinked.LinkedCount, 0) AS LinkedPostsCount,
        COALESCE(plDuplicate.DuplicateCount, 0) AS DuplicateLinksCount
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountUpVotes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) vUp ON vUp.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountDownVotes
        FROM Votes
        WHERE VoteTypeId = 3
        GROUP BY PostId
    ) vDown ON vDown.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS LinkedCount
        FROM PostLinks
        WHERE LinkTypeId = 1
        GROUP BY PostId
    ) plLinked ON plLinked.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS DuplicateCount
        FROM PostLinks
        WHERE LinkTypeId = 3
        GROUP BY PostId
    ) plDuplicate ON plDuplicate.PostId = p.Id
),
QuestionDetailedStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        COALESCE(ans.AnswerCount,0) AS AnswerCount,
        COALESCE(accAns.Score, 0) AS AcceptedAnswerScore,
        COALESCE(accAns.OwnerUserId, -1) AS AcceptedAnswerOwnerUserId,
        COALESCE(badgesForOwner.TotalBadges, 0) AS OwnerBadgeCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS QuestionScoreRank,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS QuestionChronology,
        COALESCE(v.UpVotes, 0) AS OwnerUpVotes,
        COALESCE(v.DownVotes, 0) AS OwnerDownVotes,
        CASE WHEN p.ClosedDate IS NULL THEN FALSE ELSE TRUE END AS IsClosed,
        COALESCE(ph.CloseReasonName, 'None') AS CloseReason
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) ans ON ans.ParentId = p.Id
    LEFT JOIN Posts accAns ON accAns.Id = p.AcceptedAnswerId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS TotalBadges
        FROM Badges
        GROUP BY UserId
    ) badgesForOwner ON badgesForOwner.UserId = p.OwnerUserId
    LEFT JOIN (
        SELECT
            ph.PostId,
            cht.Name AS CloseReasonName
        FROM PostHistory ph
        JOIN CloseReasonTypes cht ON CAST(ph.Comment AS int) = cht.Id
        WHERE ph.PostHistoryTypeId = 10
    ) ph ON ph.PostId = p.Id
    LEFT JOIN (
        SELECT
            u.Id,
            COALESCE(SUM(v2a.UpVotes), 0) AS UpVotes,
            COALESCE(SUM(v2a.DownVotes), 0) AS DownVotes
        FROM Users u
        LEFT JOIN (
            SELECT
                p.OwnerUserId,
                COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
                COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes
            FROM Posts p
            LEFT JOIN Votes v ON v.PostId = p.Id
            GROUP BY p.OwnerUserId
        ) v2a ON v2a.OwnerUserId = u.Id
        GROUP BY u.Id
    ) v ON v.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
CorrelatedAnswerStats AS (
    SELECT
        ans.Id AS AnswerId,
        ans.ParentId AS QuestionId,
        ans.OwnerUserId,
        ans.Score AS AnswerScore,
        ans.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY ans.ParentId ORDER BY ans.Score DESC, ans.CreationDate ASC) AS AnswerRank,
        MAX(ans.Score) OVER (PARTITION BY ans.ParentId) AS MaxAnswerScoreForQuestion,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ans.Id AND v.VoteTypeId = 14) AS ModeratorReviewCount
    FROM Posts ans
    WHERE ans.PostTypeId = 2
),
CombinedPostUserStats AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.OwnerDisplayName,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.CreationDate AS QuestionCreationDate,
        q.Tags,
        q.AnswerCount,
        q.AcceptedAnswerScore,
        q.AcceptedAnswerOwnerUserId,
        q.OwnerBadgeCount,
        q.QuestionScoreRank,
        q.QuestionChronology,
        q.OwnerUpVotes,
        q.OwnerDownVotes,
        q.IsClosed,
        q.CloseReason,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerCreationDate,
        a.AnswerRank,
        a.MaxAnswerScoreForQuestion,
        a.ModeratorReviewCount
    FROM QuestionDetailedStats q
    LEFT JOIN CorrelatedAnswerStats a ON a.QuestionId = q.QuestionId AND a.AnswerRank <= 3 -- top 3 answers only
),
FinalOutput AS (
    SELECT
        c.QuestionId,
        c.Title,
        c.OwnerDisplayName,
        c.QuestionScore,
        c.ViewCount,
        CONCAT(
            'Tags: ',
            COALESCE(NULLIF(c.Tags, ''), '<no tags>'),
            ' (AnswerCount: ', c.AnswerCount::text,
            ', AcceptedAnswerScore: ', COALESCE(c.AcceptedAnswerScore::text, '0'),
            ', OwnerBadges: ', c.OwnerBadgeCount::text,
            ', OwnerReputation: ', ua.Reputation::text,
            ', OwnerUpVotes: ', c.OwnerUpVotes::text,
            ', OwnerDownVotes: ', c.OwnerDownVotes::text,
            ', Closed: ', CASE WHEN c.IsClosed THEN 'Yes' ELSE 'No' END,
            ', CloseReason: ', c.CloseReason,
            ')'
        ) AS Summary,
        c.AnswerId,
        c.AnswerScore,
        TO_CHAR(c.AnswerCreationDate, 'YYYY-MM-DD HH24:MI:SS') AS AnswerCreationDate,
        c.AnswerRank,
        c.MaxAnswerScoreForQuestion,
        c.ModeratorReviewCount,
        ROW_NUMBER() OVER (PARTITION BY c.QuestionId ORDER BY c.AnswerScore DESC) AS AnswerRowNumber,
        ua.DisplayName AS OwnerDisplayNameFull,
        ua.Reputation AS OwnerReputation,
        ua.CreationDate AS OwnerCreation,
        ua.Views AS OwnerViews,
        ua.UpVotes AS OwnerTotalUpVotes,
        ua.DownVotes AS OwnerTotalDownVotes,
        -- Complex calculation including string length, NULL logic, and arithmetic
        LENGTH(COALESCE(c.Title, '')) * COALESCE(NULLIF(c.Score, 0), 1) +
        CASE WHEN c.IsClosed THEN 50 ELSE 0 END -
        COALESCE(c.AcceptedAnswerScore, 0) * 2+
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = c.QuestionId AND ph.PostHistoryTypeId = 5) AS ComplicatedScore,
        -- String expression concatenating OwnerDisplayName with badges and reputation
        CONCAT(ua.DisplayName, ' (#Badges:', COALESCE(b.BadgeCount::text, '0'), ', Rep: ', ua.Reputation::text, ')') AS OwnerCompactInfo
    FROM CombinedPostUserStats c
    JOIN Users ua ON ua.Id = c.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId
    ) b ON b.UserId = c.OwnerUserId
    WHERE c.QuestionScoreRank <= 10
      AND c.AnswerScore IS NOT NULL
),
UnionAllAnswersByScore AS (
    SELECT
        QuestionId,
        AnswerId,
        AnswerScore,
        AnswerRank,
        AnswerCreationDate
    FROM CorrelatedAnswerStats
    WHERE AnswerScore >= 10

    UNION ALL

    SELECT
        QuestionId,
        AnswerId,
        AnswerScore,
        AnswerRank,
        AnswerCreationDate
    FROM CorrelatedAnswerStats
    WHERE ModeratorReviewCount > 0
),
FilteredFinalOutput AS (
    SELECT DISTINCT
        fo.*
    FROM FinalOutput fo
    LEFT JOIN UnionAllAnswersByScore uas ON uas.AnswerId = fo.AnswerId
    WHERE uas.AnswerId IS NOT NULL
)
SELECT
    f.QuestionId,
    f.Title,
    f.OwnerDisplayName,
    f.QuestionScore,
    f.ViewCount,
    f.Summary,
    f.AnswerId,
    f.AnswerScore,
    f.AnswerCreationDate,
    f.AnswerRank,
    f.MaxAnswerScoreForQuestion,
    f.ModeratorReviewCount,
    f.AnswerRowNumber,
    f.OwnerDisplayNameFull,
    f.OwnerReputation,
    f.OwnerCreation,
    f.OwnerViews,
    f.OwnerTotalUpVotes,
    f.OwnerTotalDownVotes,
    f.ComplicatedScore,
    f.OwnerCompactInfo
FROM FilteredFinalOutput f
ORDER BY f.QuestionScore DESC, f.AnswerScore DESC, f.AnswerCreationDate ASC
LIMIT 100;
