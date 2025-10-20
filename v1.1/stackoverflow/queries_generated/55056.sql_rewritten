-- {"query": "55056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1373} 
WITH base_posts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.Reputation,
        u.CreationDate AS UserCreation,
        COALESCE(a.AnsCnt, 0)      AS AnswerCount,
        COALESCE(v.UpCnt, 0)       AS UpVotes,
        COALESCE(v.DownCnt, 0)     AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn_hist
    FROM Posts p
    JOIN Users u               ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnsCnt
        FROM Posts
        WHERE PostTypeId = 2          -- answers
        GROUP BY ParentId
    ) a                         ON p.Id = a.ParentId
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpCnt,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownCnt
        FROM Votes
        GROUP BY PostId
    ) v                         ON p.Id = v.PostId
    LEFT JOIN PostHistory ph   ON ph.PostId = p.Id
                                 AND ph.PostHistoryTypeId IN (4,5,6)   -- edits
),
tagged AS (
    SELECT
        bp.Id,
        bp.Title,
        bp.Score,
        bp.ViewCount,
        bp.AnswerCount,
        bp.UpVotes,
        bp.DownVotes,
        bp.Reputation,
        bp.CreationDate,
        unnest(string_to_array(trim(both '<>' FROM bp.Tags), '><')) AS Tag,
        bp.rn_hist
    FROM base_posts bp
    WHERE bp.PostTypeId = 1               -- only questions
),
tag_aggregates AS (
    SELECT
        Tag,
        COUNT(*)                                 AS QuestionCount,
        AVG(Score)                               AS AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ViewCount) AS MedianViews,
        MAX(ViewCount)                           AS MaxViews,
        SUM(UpVotes)                             AS TotalUpVotes,
        SUM(DownVotes)                           AS TotalDownVotes
    FROM tagged
    GROUP BY Tag
),
top_tags AS (
    SELECT Tag
    FROM tag_aggregates
    ORDER BY QuestionCount DESC
    LIMIT 10
)
SELECT
    t.Id,
    t.Title,
    t.Tag,
    t.Score,
    t.ViewCount,
    t.AnswerCount,
    t.UpVotes,
    t.DownVotes,
    t.Reputation,
    t.CreationDate
FROM tagged t
JOIN top_tags tt ON t.Tag = tt.Tag
WHERE t.rn_hist = 1               -- most recent revision for each post
ORDER BY t.Score DESC, t.ViewCount DESC
LIMIT 100;