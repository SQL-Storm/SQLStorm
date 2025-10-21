-- {"query": "121.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1224} 
WITH
-- 1) Recent high-activity questions with complex multi-join signals
RecentActive as (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        u.Reputation
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '90 days')
),
-- 2) Latest edits per post (if any)
LatestEdits as (
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,14,15,16,17,18,19,20,22,24,33,34)
),
-- 3) Aggregate vote activity (upvotes/downvotes) per post in last 90 days
RecentVotes as (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesInWindow,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesInWindow,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '90 days')
    GROUP BY v.PostId
),
-- 4) Tag-based surface: count distinct tag names from Tags for question posts
TagStats as (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COUNT(*) AS TagPostCount,
        SUM(CASE WHEN t.IsModeratorOnly = TRUE THEN 1 ELSE 0 END) AS ModeratorOnlyCount
    FROM Tags t
    GROUP BY t.Id, t.TagName
),
-- 5) Correlated subquery: number of answers for each question (undeleted only)
AnswerCounts as (
    SELECT
        p.Id AS PostId,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1
)
-- 6) Assemble benchmarking result with various constructs: outer joins, CTEs, window, NULL handling, set ops
SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.Tags,
    rq.OwnerName,
    rq.Reputation,
    le.EditDate,
    le.UserDisplayName AS LastEditor,
    rv.LastVoteDate,
    rv.UpVotesInWindow,
    rv.DownVotesInWindow,
    ta.TagName AS PrimaryTag,
    ac.AnswerCount,
    -- Complex computed column: engagement score with NULL-safe arithmetic and coalescing
    COALESCE(rq.ViewCount, 0) * 1.0
      + COALESCE(rv.UpVotesInWindow, 0) * 2.0
      - COALESCE(rv.DownVotesInWindow, 0) * 1.5
      + COALESCE(ac.AnswerCount, 0) * 3.0
      AS EngagementScore
FROM RecentActive rq
LEFT JOIN LatestEdits le ON le.PostId = rq.PostId
LEFT JOIN RecentVotes rv ON rv.PostId = rq.PostId
LEFT JOIN AnswerCounts ac ON ac.PostId = rq.PostId
LEFT JOIN LATERAL (
    SELECT t.TagName
    FROM unnest(string_to_array(rq.Tags, '><')) AS t(TagName)
    ORDER BY t.TagName
    LIMIT 1
) AS t0 ON TRUE
LEFT JOIN Tags ta ON ta.TagName = t0.TagName
WHERE
    rq.Score > 0
    OR (rq.ViewCount > 100 AND rv.LastVoteDate IS NOT NULL)
UNION ALL
SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.Tags,
    rq.OwnerName,
    rq.Reputation,
    NULL AS EditDate,
    NULL AS LastEditor,
    NULL AS LastVoteDate,
    0 AS UpVotesInWindow,
    0 AS DownVotesInWindow,
    NULL AS PrimaryTag,
    0 AS AnswerCount,
    -- Alternative expression for diversification in benchmark
    COALESCE(rq.ViewCount, 0) * 0.5
      + COALESCE(rq.Score, 0) * 1.25
      + COALESCE(rq.ViewCount, 0) * COALESCE(rv.UpVotesInWindow, 0) * 0.0
      AS EngagementScore
FROM RecentActive rq
LEFT JOIN RecentVotes rv ON rv.PostId = rq.PostId
WHERE rq.OwnerName IS NULL
ORDER BY EngagementScore DESC
LIMIT 100;