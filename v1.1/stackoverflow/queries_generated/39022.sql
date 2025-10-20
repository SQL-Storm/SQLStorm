-- {"query": "39022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2470} 

WITH recent_questions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
question_activity AS (
    SELECT
        rq.Id AS question_id,
        COUNT(DISTINCT c.Id)                                    AS comment_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2)     AS upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3)     AS downvotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS edits
    FROM recent_questions rq
    LEFT JOIN Comments      c  ON c.PostId      = rq.Id
    LEFT JOIN Votes         v  ON v.PostId      = rq.Id
    LEFT JOIN PostHistory   ph ON ph.PostId     = rq.Id
    GROUP BY rq.Id
),
user_profile AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
        COUNT(DISTINCT ph2.Id) FILTER (WHERE ph2.PostHistoryTypeId = 24) AS suggestions_approved
    FROM Users u
    LEFT JOIN Badges      b   ON b.UserId     = u.Id
    LEFT JOIN PostHistory ph2 ON ph2.UserId    = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_hotness AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT pl.PostId) FILTER (WHERE pl.LinkTypeId = 1) AS inbound_links,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS duplicates,
        qcnt.question_count
    FROM Tags t
    LEFT JOIN PostLinks pl
        ON pl.PostId       = t.ExcerptPostId
        OR pl.RelatedPostId = t.ExcerptPostId
    LEFT JOIN (
        SELECT
            unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag,
            COUNT(*) AS question_count
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY 1
    ) qcnt ON qcnt.tag = t.TagName
    WHERE t.IsRequired = 0
    GROUP BY t.TagName, qcnt.question_count
    HAVING COUNT(DISTINCT pl.PostId) > 100
)
SELECT
    rq.rn,
    rq.Id,
    rq.Title,
    qa.comment_count,
    qa.upvotes,
    qa.downvotes,
    qa.edits,
    up.DisplayName,
    up.Reputation,
    up.gold_badges,
    up.silver_badges,
    up.bronze_badges,
    up.suggestions_approved,
    th.TagName,
    th.inbound_links,
    th.duplicates,
    th.question_count,
    RANK() OVER (
        PARTITION BY th.TagName
        ORDER BY qa.upvotes DESC, qa.comment_count DESC
    ) AS tag_rank
FROM recent_questions rq
JOIN question_activity qa   ON qa.question_id = rq.Id
JOIN user_profile    up    ON up.Id          = rq.OwnerUserId
JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rq.Tags,2,length(rq.Tags)-2),'><')) AS tag
) tq ON TRUE
JOIN tag_hotness th     ON th.TagName      = tq.tag
WHERE rq.rn <= 1000
ORDER BY rq.CreationDate DESC, th.inbound_links DESC, up.Reputation DESC
LIMIT 100;
