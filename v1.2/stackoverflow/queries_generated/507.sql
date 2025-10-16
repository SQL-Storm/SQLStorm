-- {"query": "507.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1509} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> r.Id AND t.Count < r.Count
    WHERE r.Level < 3
),
UserBadgeRankings AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class, COUNT(*) DESC) AS BadgeRank
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore,
        MAX(ph.CreationDate) AS LastPostEdit
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    WHERE u.Reputation > 1000 AND u.CreationDate < NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views
),
PostWithAggregates AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(DISTINCT c.Id) AS CommentCountReal,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.AcceptedAnswerId, p.Title, p.AnswerCount, p.CommentCount, p.FavoriteCount
),
AcceptedAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId AS QuestionOwner,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwner,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAccept,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST) AS AnswerScoreRank
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateCount
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    u.QuestionCount,
    u.AnswerCount,
    u.CommentCount,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.BadgeCount, 0) AS RecentBadgeCount,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount AS PostAnswerCount,
    p.CommentCountReal,
    p.UpVotes AS PostUpVotes,
    p.DownVotes AS PostDownVotes,
    pls.LinkedCount,
    pls.DuplicateCount,
    aa.AnswerId,
    aa.AnswerScore,
    aa.HoursToAccept,
    CASE 
        WHEN aa.HoursToAccept IS NULL THEN 'No Accepted Answer'
        WHEN aa.HoursToAccept < 1 THEN 'Accepted Quickly'
        WHEN aa.HoursToAccept BETWEEN 1 AND 24 THEN 'Accepted Within a Day'
        ELSE 'Accepted Late'
    END AS AcceptanceSpeedCategory,
    rh.Level AS TagHierarchyLevel,
    array_to_string(rh.TagPath, ' > ') AS TagHierarchyPath
FROM TopUsers u
LEFT JOIN UserBadgeRankings b ON b.UserId = u.Id AND b.BadgeRank = 1
LEFT JOIN PostWithAggregates p ON p.OwnerUserId = u.Id
LEFT JOIN PostLinkSummary pls ON pls.PostId = p.Id
LEFT JOIN AcceptedAnswerStats aa ON aa.QuestionId = p.Id
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(COALESCE(p.Tags, ''), '><'))
WHERE p.ScoreRank <= 10
  AND (p.Tags IS NOT NULL AND p.Tags <> '')
  AND (u.Location IS NOT NULL AND u.Location <> '')
ORDER BY u.Reputation DESC, p.Score DESC, aa.HoursToAccept NULLS LAST
LIMIT 100;
