-- {"query": "864.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1294} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        0 AS Depth,
        CAST(t.TagName AS VARCHAR(1000)) AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        parent.Depth + 1,
        parent.Path || ' > ' || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.Id <> parent.Id
    WHERE child.IsModeratorOnly = 0 AND child.IsRequired = 0
      AND LENGTH(parent.Path) < 1000
),
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        u.CreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Class) AS HighestBadgeClass,
        AVG(COALESCE(v.Score, 0)) AS AvgVoteScore,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS LocationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        ph.Comment AS CloseReason,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
    WHERE p.PostTypeId = 1
      AND (ph.Id IS NULL OR ph.Comment IS NULL) -- not closed or no close reason
      AND p.Score > 10
),
AnswersWithAcceptedFlag AS (
    SELECT
        a.Id,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        a.Body
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN c.CreationDate > now() - INTERVAL '30 days' THEN 1 ELSE 0 END) AS RecentComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UnionVotesCounts AS (
    SELECT PostId, COUNT(*) AS UpVotes
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId

    UNION ALL

    SELECT PostId, COUNT(*) * -1 AS DownVotes
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
),
AggregatedVotes AS (
    SELECT
        PostId,
        SUM(UpVotes) AS UpVotes,
        SUM(DownVotes) AS DownVotes,
        SUM(UpVotes) + SUM(DownVotes) AS NetVotes
    FROM UnionVotesCounts
    GROUP BY PostId
)
SELECT
    ua.Id AS UserId,
    ua.DisplayName,
    ua.Location,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeCount,
    ua.HighestBadgeClass,
    ua.AvgVoteScore,
    ua.LocationRank,
    tq.Id AS TopQuestionId,
    tq.Title AS TopQuestionTitle,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tq.AnswerCount AS QuestionAnswerCount,
    tq.FavoriteCount,
    COALESCE(tq.CloseReason, 'Open') AS QuestionStatus,
    awaf.Id AS AnswerId,
    awaf.Score AS AnswerScore,
    awaf.IsAccepted,
    COALESCE(ucs.CommentCount, 0) AS UserCommentCount,
    COALESCE(ucs.AvgCommentLength, 0) AS AvgCommentLength,
    COALESCE(ucs.RecentComments, 0) AS RecentUserComments,
    av.UpVotes,
    av.DownVotes,
    av.NetVotes,
    rh.Depth AS TagHierarchyDepth,
    rh.Path AS TagHierarchyPath
FROM UserActivity ua
LEFT JOIN TopQuestions tq ON tq.OwnerUserId = ua.Id
LEFT JOIN AnswersWithAcceptedFlag awaf ON awaf.OwnerUserId = ua.Id
LEFT JOIN UserCommentStats ucs ON ucs.UserId = ua.Id
LEFT JOIN AggregatedVotes av ON av.PostId = awaf.Id
LEFT JOIN RecursiveTagHierarchy rh ON rh.ExcerptPostId = tq.Id OR rh.WikiPostId = tq.Id
WHERE ua.Location IS NOT NULL
  AND ua.Reputation > 1000
  AND (awaf.IsAccepted = 1 OR awaf.IsAccepted IS NULL)
  AND (tq.Score IS NULL OR tq.Score > 20)
ORDER BY ua.Reputation DESC, tq.Score DESC NULLS LAST
LIMIT 100;
