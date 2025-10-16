-- {"query": "24062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3003} 

-- Construct tag rows from the tags string (delimited by "<>")
WITH TagRows AS (
    SELECT p.Id            AS PostId,
           TRIM(both '>' FROM unnest(string_to_array(p.Tags, '<>'))) AS Tag,
           p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1
),

-- Aggregate statistics per tag
TagAgg AS (
    SELECT Tag,
           COUNT(*)                                 AS QCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LastUpvote
    FROM TagRows tr
    LEFT JOIN Votes v ON v.PostId = tr.PostId
    GROUP BY Tag
),

-- Get the first close reason per question
CloseR AS (
    SELECT ph.PostId,
           ph.Comment AS CloseReason,
           MIN(ph.CreationDate) AS FirstClosed
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, ph.Comment
),

-- Get duplicate links
Dup AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           lt.Name AS DuplicateOf
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Id = 3
),

-- Base questions (includes null logic for missing data)
BaseQuestions AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.ViewCount,
           p.OwnerUserId,
           p.AcceptedAnswerId,
           COALESCE(cr.CloseReason, 'N/A')         AS CloseReason,
           COALESCE(cr.FirstClosed, '1900-01-01')   AS FirstClosed,
           COALESCE(d.DuplicateOf, 'None')          AS DuplicateOf
    FROM Posts p
    LEFT JOIN CloseR cr ON cr.PostId = p.Id
    LEFT JOIN Dup d ON d.PostId = p.Id
    WHERE p.PostTypeId = 1
),

-- Union questions with duplicate rows to exercise set operators
AllPosts AS (
    SELECT * FROM BaseQuestions
    UNION ALL
    SELECT
        d.PostId AS Id,
        ''::varchar AS Title,
        0::int AS Score,
        0::int AS ViewCount,
        d.RelatedPostId AS OwnerUserId,
        NULL::int AS AcceptedAnswerId,
        ''::varchar AS CloseReason,
        '1900-01-01'::timestamp AS FirstClosed,
        d.DuplicateOf AS DuplicateOf
    FROM Dup d
),

-- Window function: rank questions per user
Ranked AS (
    SELECT ap.*,
           ROW_NUMBER() OVER (PARTITION BY ap.OwnerUserId
                              ORDER BY ap.Score DESC, ap.ViewCount DESC) AS OwnerRank
    FROM AllPosts ap
),

-- Correlated sub‑query to fetch the first version of the title (outer join logic)
TitleHistory AS (
    SELECT p.Id,
           COALESCE(th.Title, p.Title) AS FirstTitle
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT ph.Text AS Title
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
          AND ph.PostHistoryTypeId = 1   -- initial title
        ORDER BY ph.CreationDate
        LIMIT 1
    ) th ON true
)

-- Final select: join several sources, use window functions, set operators, complex predicates & NULL logic
SELECT
    r.Id,
    r.Title,
    r.FirstTitle,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerDisplayName,
    r.AcceptedAnswerId,
    r.CloseReason,
    r.FirstClosed,
    r.DuplicateOf,
    r.OwnerRank,
    ta.QCount,
    ta.UpVotes,
    ta.DownVotes,
    ta.LastUpvote
FROM Ranked r
JOIN TitleHistory th ON th.Id = r.Id
JOIN TagAgg ta ON ta.Tag = ANY (string_to_array(r.Title, ' '))
WHERE r.Score > 0                 -- complicated predicate
  AND (r.CloseReason <> 'N/A' OR r.FirstClosed > '2022-01-01')
ORDER BY r.Score DESC, r.ViewCount DESC
LIMIT 1000;
