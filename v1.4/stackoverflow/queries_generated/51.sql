-- {"query": "51.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1019} 
WITH
-- sample derived usage: identify high-traffic, highly upvoted questions with complex history
QuestionStats AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastActivityDate,
        p.Tags,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        u.Reputation,
        u.DisplayName AS OwnerDisplayName,
        -- total number of edits and closings from PostHistory
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6,8,9,16,36)) AS EditCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13,14,15,19,20,35,36)) AS CloseOrOpenCount,
        -- a complex computed metric combining views, score and recency
        (p.ViewCount * 2 + p.Score * 3) / NULLIF(DATEDIFF(day, p.CreationDate, CURRENT_DATE), 0) AS EngagementRate
    FROM
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1 -- questions
        AND p.DeletionDate IS NULL
),
-- correlate with edges from PostLinks to discover clusters of related content
Links AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name AS LinkTypeName
    FROM
        PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE
        lt.Name IN ('Linked', 'Duplicate')
),
-- windowed ranking of questions by engagement and recency
Ranked AS (
    SELECT
        qs.*,
        ROW_NUMBER() OVER (
            PARTITION BY qs.OwnerUserId
            ORDER BY
                qs.EngagementRate DESC,
                qs.LastActivityDate DESC,
                qs.Score DESC
        ) AS rn
    FROM
        QuestionStats qs
    WHERE
        qs.EngagementRate > 0
        AND qs.Reputation > 100
),
-- attempt to pull a correlated subquery: top related post with most votes per cluster
TopRelated AS (
    SELECT
        r.PostId,
        r.RelatedPostId,
        r.LinkTypeName,
        (
            SELECT MAX(v.BountyAmount)
            FROM Votes v
            WHERE v.PostId = r.RelatedPostId
            AND v.VoteTypeId = 8
        ) AS TopBounty,
        (
            SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = r.RelatedPostId
        ) AS RelatedPostVotes
    FROM
        Links r
),
-- final composite with aggregation and conditional logic
Final AS (
    SELECT
        ro.PostId,
        ro.Title,
        ro.OwnerDisplayName,
        ro.Reputation,
        ro.CreationDate,
        ro.LastActivityDate,
        ro.ViewCount,
        ro.Score,
        ro.AnswerCount,
        ro.CommentCount,
        ro.EditCount,
        ro.CloseOrOpenCount,
        ro.EngagementRate,
        STRING_AGG(DISTINCT t.TagName, ',') AS TagList,
        fu.RelatedPostId AS ClusterRelatedPostId,
        fu.LinkTypeName,
        fu.TopBounty,
        fu.RelatedPostVotes
    FROM
        Ranked ro
        LEFT JOIN LATERAL (
            SELECT
                l.RelatedPostId,
                l.LinkTypeName
            FROM
                TopRelated l
            WHERE
                l.PostId = ro.Id
            ORDER BY l.RelatedPostVotes DESC
            LIMIT 1
        ) fu ON TRUE
        LEFT JOIN Tags t ON t.Id = (
            SELECT CAST(SPLIT_PART(tg, '><', n.n) AS INT)
            FROM (SELECT UNNEST(string_to_array(ro.Tags, ', ')) AS tg) s
            CROSS JOIN LATERAL generate_series(1, 5) n
            LIMIT 1
        )
    GROUP BY
        ro.PostId, ro.Title, ro.OwnerDisplayName, ro.Reputation, ro.CreationDate, ro.LastActivityDate,
        ro.ViewCount, ro.Score, ro.AnswerCount, ro.CommentCount, ro.EditCount, ro.CloseOrOpenCount,
        ro.EngagementRate, fu.RelatedPostId, fu.LinkTypeName, fu.TopBounty, fu.RelatedPostVotes
)
SELECT
    *
FROM
    Final
ORDER BY
    EngagementRate DESC
LIMIT 100;