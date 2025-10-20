WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
      AND p.AnswerCount IS NOT NULL
      AND p.Score > 10
),
-- Normalize tags by splitting the Tags string into rows using a standard approach (UNNEST on string_to_array).
-- This version uses a derived table to split tags; it should work on Postgres and many other DBs supporting string functions.
PostTags AS (
    SELECT
        p.Id AS PostId,
        trim(both ' ' FROM t) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
            replace(replace(coalesce(p.Tags, ''), '<', ''), '>', ''), '|'
        )) AS t
    ) s
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
),
TagPopularity AS (
    SELECT
        pt.TagName,
        COUNT(pt.PostId) AS PostCount,
        SUM(p.Score) AS TotalScore
    FROM PostTags pt
    JOIN Posts p ON p.Id = pt.PostId
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
    GROUP BY pt.TagName
    ORDER BY COUNT(pt.PostId) DESC
    LIMIT 50
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END), 0) AS BodyEdits,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END), 0) AS BodyRevisions,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 1 THEN 1 ELSE 0 END), 0) AS TitleEdits,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END), 0) AS TitleRevisions,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 3 THEN 1 ELSE 0 END), 0) AS TagEdits,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END), 0) AS TagRevisions,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        u.Reputation
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    ORDER BY u.Reputation DESC
    LIMIT 100
)
SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate AS PostCreationDate,
    rp.Score AS PostScore,
    rp.ViewCount AS PostViewCount,
    rp.AnswerCount AS PostAnswerCount,
    tp.TagName,
    tp.PostCount AS TagPostCount,
    tp.TotalScore AS TagTotalScore,
    ua.UserId,
    ua.DisplayName AS UserDisplayName,
    ua.Reputation,
    ua.BodyEdits,
    ua.BodyRevisions,
    ua.TitleEdits,
    ua.TitleRevisions,
    ua.TagEdits,
    ua.TagRevisions,
    ua.CommentCount AS UserCommentCount,
    ua.VoteCount AS UserVoteCount,
    ua.UpVotes AS UserUpVotes,
    ua.DownVotes AS UserDownVotes
FROM RankedPosts rp
CROSS JOIN TagPopularity tp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN UserActivity ua ON u.Id = ua.UserId
WHERE rp.RowNum <= 100
ORDER BY rp.RowNum, tp.PostCount DESC;