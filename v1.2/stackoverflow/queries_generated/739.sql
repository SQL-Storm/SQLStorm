-- {"query": "739.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1759} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        1 AS Level,
        ARRAY[t.TagName] AS Path
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        r.Level + 1,
        r.Path || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.ExcerptPostId = r.Id
    WHERE t2.IsRequired = 1 AND NOT t2.TagName = ANY(r.Path)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COALESCE(SUM(vb.BountyAmount),0) AS TotalBountyGiven,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes vb ON vb.UserId = u.Id AND vb.VoteTypeId = 8
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        COALESCE(vu.UpVotes,0) AS UpVotes,
        COALESCE(vd.DownVotes,0) AS DownVotes,
        COALESCE(bc.BadgeCount,0) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRankByUser
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS UpVotes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) vu ON vu.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS DownVotes
        FROM Votes
        WHERE VoteTypeId = 3
        GROUP BY PostId
    ) vd ON vd.PostId = p.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
),
ClosedQuestions AS (
    SELECT 
        ph.PostId,
        MIN(ph.CreationDate) AS FirstClosedDate,
        STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
    GROUP BY ph.PostId
),
TopUsersQuestions AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        pe.PostId,
        pe.Title,
        pe.Score,
        pe.ViewCount,
        pe.UpVotes,
        pe.DownVotes,
        pe.BadgeCount,
        cq.FirstClosedDate,
        cq.CloseReasons,
        ua.UserRank
    FROM UserActivity ua
    JOIN PostEngagement pe ON pe.OwnerUserId = ua.UserId AND pe.PostRankByUser <= 3
    LEFT JOIN ClosedQuestions cq ON cq.PostId = pe.PostId
    WHERE ua.QuestionsPosted > 10
),
AcceptedAnswersDetails AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererId,
        u.DisplayName AS AnswererName,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate) AS AnswerRank
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
),
AnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        COUNT(a.AnswerId) AS TotalAnswers,
        MAX(CASE WHEN a.AnswerId = q.AcceptedAnswerId THEN a.AnswerScore ELSE NULL END) AS AcceptedAnswerScore,
        AVG(a.AnswerScore) AS AvgAnswerScore,
        MAX(a.AnswerScore) AS MaxAnswerScore,
        MIN(a.AnswerScore) AS MinAnswerScore
    FROM Posts q
    LEFT JOIN AcceptedAnswersDetails a ON a.QuestionId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
)
SELECT 
    tuq.UserRank,
    tuq.DisplayName AS User,
    tuq.PostId,
    tuq.Title,
    tuq.Score AS QuestionScore,
    tuq.ViewCount,
    tuq.UpVotes,
    tuq.DownVotes,
    tuq.BadgeCount,
    COALESCE(tuq.FirstClosedDate, TIMESTAMP '9999-12-31') AS ClosedDate,
    tuq.CloseReasons,
    ans.TotalAnswers,
    ans.AcceptedAnswerScore,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.MinAnswerScore,
    -- Complex string manipulation: Extract first tag and count tags
    split_part(substring(tuq.Tags FROM 2 FOR char_length(tuq.Tags)-2), '><', 1) AS FirstTag,
    cardinality(string_to_array(substring(tuq.Tags FROM 2 FOR char_length(tuq.Tags)-2), '><')) AS TagCount,
    -- Correlated subquery: Count comments on the question by distinct users excluding the owner
    (SELECT COUNT(DISTINCT c.UserId) 
     FROM Comments c 
     WHERE c.PostId = tuq.PostId AND c.UserId IS NOT NULL AND c.UserId <> tuq.UserId) AS DistinctCommenters,
    -- NULL logic: Whether the user has a website or not
    CASE WHEN EXISTS (SELECT 1 FROM Users u WHERE u.Id = tuq.UserId AND u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '') THEN 'Has Website' ELSE 'No Website' END AS WebsitePresence
FROM TopUsersQuestions tuq
LEFT JOIN AnswerStats ans ON ans.QuestionId = tuq.PostId
WHERE tuq.ClosedDate IS NULL OR tuq.ClosedDate > NOW() - INTERVAL '1 year'

UNION

SELECT 
    ua.UserRank,
    ua.DisplayName,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    COALESCE(vu.UpVotes,0),
    COALESCE(vd.DownVotes,0),
    COALESCE(bc.BadgeCount,0),
    NULL AS ClosedDate,
    NULL AS CloseReasons,
    0 AS TotalAnswers,
    NULL AS AcceptedAnswerScore,
    NULL AS AvgAnswerScore,
    NULL AS MaxAnswerScore,
    NULL AS MinAnswerScore,
    NULL AS FirstTag,
    NULL AS TagCount,
    0 AS DistinctCommenters,
    'No Website' AS WebsitePresence
FROM UserActivity ua
JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.PostTypeId = 2
LEFT JOIN (
    SELECT PostId, COUNT(*) AS UpVotes
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
) vu ON vu.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS DownVotes
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
) vd ON vd.PostId = p.Id
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
) bc ON bc.UserId = ua.UserId
WHERE ua.UserRank <= 10

ORDER BY UserRank, Score DESC, ViewCount DESC
LIMIT 100;
