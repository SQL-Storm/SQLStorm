-- {"query": "54014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1798} 

WITH
-- Basic metadata for each question
Q AS (
    SELECT
        p.Id                                        AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.Reputation                                AS OwnerRep,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount,
        MAX(ph.CreationDate)                                 AS LastEditDate
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, u.Reputation
),
-- Vote aggregation per post
VoteStats AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)  AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)  AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END)  AS Accepted
    FROM Votes v
    GROUP BY v.PostId
),
-- Duplicate relationships
DuplicateInfo AS (
    SELECT
        pl.PostId           AS QuestionId,
        COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
        STRING_AGG(DISTINCT CAST(pl.RelatedPostId AS TEXT), ',') AS DuplicatedPostIds
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
-- Tag metrics: total questions and score per tag
TagMetrics AS (
    SELECT
        t.TagName,
        COUNT(*)        AS QuestionCount,
        SUM(p.Score)    AS TotalScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%', t.TagName, '%')  -- crude match; replace with proper split if needed
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
-- Join each question with its tags and tag metrics
TaggedQ AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.OwnerRep,
        q.EditCount,
        q.LastEditDate,
        vs.Upvotes,
        vs.Downvotes,
        vs.Accepted,
        di.DuplicateCount,
        di.DuplicatedPostIds,
        tm.TagName,
        tm.QuestionCount,
        tm.TotalScore
    FROM Q q
    LEFT JOIN VoteStats vs ON vs.PostId = q.QuestionId
    LEFT JOIN DuplicateInfo di ON di.QuestionId = q.QuestionId
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
    ) AS tagList(TagName) ON true
    LEFT JOIN TagMetrics tm ON tm.TagName = tagList.TagName
)
-- Final selection of interesting & elaborate metrics
SELECT
    QuestionId,
    Title,
    Tags,
    CreationDate,
    Score,
    ViewCount,
    OwnerRep,
    EditCount,
    LastEditDate,
    Upvotes,
    Downvotes,
    Accepted,
    DuplicateCount,
    DuplicatedPostIds,
    TagName,
    QuestionCount,
    TotalScore
FROM TaggedQ
ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST, EditCount DESC
LIMIT 100;
