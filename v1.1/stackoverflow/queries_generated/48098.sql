-- {"query": "48098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 955} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS RowNum
    FROM Posts AS p
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.CreationDate >= DATE('now', '-365 days') -- Last year
      AND p.AnswerCount IS NOT NULL
      AND p.Score > 10
),
TagPopularity AS (
    SELECT
        t.TagName,
        COUNT(pt.PostId) AS PostCount,
        SUM(p.Score) AS TotalScore
    FROM Tags AS t
    JOIN Posts AS p ON p.PostTypeId = 1
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '|') AS Tags
    WHERE Tags.value = t.TagName
      AND p.CreationDate >= DATE('now', '-365 days')
    GROUP BY t.TagName
    ORDER BY PostCount DESC
    LIMIT 50
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE NULL END) AS BodyEdits, -- Initial Body
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE NULL END) AS BodyRevisions, -- Edit Body
        COUNT(CASE WHEN ph.PostHistoryTypeId = 1 THEN 1 ELSE NULL END) AS TitleEdits, -- Initial Title
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE NULL END) AS TitleRevisions, -- Edit Title
        COUNT(CASE WHEN ph.PostHistoryTypeId = 3 THEN 1 ELSE NULL END) AS TagEdits, -- Initial Tags
        COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE NULL END) AS TagRevisions, -- Edit Tags
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Users AS u
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId AND ph.CreationDate >= DATE('now', '-365 days')
    LEFT JOIN Comments AS c ON u.Id = c.UserId AND c.CreationDate >= DATE('now', '-365 days')
    LEFT JOIN Votes AS v ON u.Id = v.UserId AND v.CreationDate >= DATE('now', '-365 days')
    GROUP BY u.Id, u.DisplayName
    ORDER BY UserActivity.Reputation DESC
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
FROM RankedPosts AS rp
CROSS JOIN TagPopularity AS tp
JOIN Users AS u ON rp.OwnerUserId = u.Id
LEFT JOIN UserActivity AS ua ON u.Id = ua.UserId
WHERE rp.RowNum <= 100 -- Top 100 viewed/scored questions
ORDER BY rp.RowNum, tp.PostCount DESC;
