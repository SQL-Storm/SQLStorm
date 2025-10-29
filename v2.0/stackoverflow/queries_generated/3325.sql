-- {"query": "3325.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2618} 

/*  Benchmark‑style query using CTEs, window functions, outer joins,
    correlated subqueries, set operators, complex predicates and NULL logic   */
WITH
/*-----------------------------------------------------------
  Per‑user aggregates (questions, answers, votes, badges, etc.)
-----------------------------------------------------------*/
UserAgg AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown')                AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)    AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)    AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)   AS AnswerScoreSum,
        COUNT(b.Id)                                   AS BadgeCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)        AS GoldBadgeCount,
        COUNT(c.Id)                                   AS CommentCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)   AS UpVoteCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)   AS DownVoteCount,
        MAX(p.CreationDate)                           AS LastPostDate,
        MIN(p.CreationDate)                           AS FirstPostDate
    FROM Users u
    LEFT JOIN Posts      p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges     b ON b.UserId      = u.Id
    LEFT JOIN Comments   c ON c.UserId      = u.Id
    LEFT JOIN Votes      v ON v.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

/*-----------------------------------------------------------
  Rank users by a composite score (reputation + gold badges + answer score)
-----------------------------------------------------------*/
UserRank AS (
    SELECT
        *,
        RANK()   OVER (ORDER BY (Reputation + GoldBadgeCount*1000 + AnswerScoreSum) DESC) AS CompositeRank,
        ROW_NUMBER()
            OVER (PARTITION BY COALESCE(NULLIF(Location, ''), 'Unknown')
                  ORDER BY Reputation DESC)                                          AS RowInLocation
    FROM UserAgg
),

/*-----------------------------------------------------------
  Per‑tag aggregates – tag usage based on the Posts.Tags column
-----------------------------------------------------------*/
TagAgg AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count                                 AS TagUseCount,
        COALESCE(e.Title, '')                   AS ExcerptTitle,
        COALESCE(w.Title, '')                   AS WikiTitle,
        (SELECT COUNT(p.Id)
         FROM Posts p
         WHERE p.Tags IS NOT NULL
           AND p.Tags LIKE '%'||'<'||t.TagName||'>'||'%')   AS PostLinkCount
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),

/*-----------------------------------------------------------
  Filtered top users (complex predicate with NULL handling)
-----------------------------------------------------------*/
TopUsers AS (
    SELECT
        ur.Id,
        ur.DisplayName,
        ur.Reputation,
        ur.GoldBadgeCount,
        ur.AnswerScoreSum,
        ur.QuestionCount,
        ur.AnswerCount,
        ur.CommentCount,
        ur.UpVoteCount,
        ur.DownVoteCount,
        ur.CompositeRank,
        ur.Location,
        CASE
            WHEN ur.Location IS NULL               THEN 'NoLocation'
            WHEN LOWER(ur.Location) LIKE '%usa%'   THEN 'USA'
            ELSE                                    'Other'
        END                                      AS LocationGroup,
        CONCAT(ur.DisplayName, ' (', COALESCE(ur.Location, 'N/A'), ')')
                                                AS DisplayWithLoc,
        (SELECT COUNT(*)
         FROM Posts p2
         WHERE p2.OwnerUserId = ur.Id
           AND p2.PostTypeId = 2
           AND p2.Score > 0)                   AS PositiveAnswerCount
    FROM UserRank ur
    WHERE (ur.Reputation > 2000 AND (ur.BadgeCount > 5 OR ur.AnswerCount > 10))
          OR (ur.Location IS NOT NULL AND LOWER(ur.Location) LIKE '%usa%')
),

/*-----------------------------------------------------------
  Filtered top tags
-----------------------------------------------------------*/
TopTags AS (
    SELECT
        ta.TagName,
        ta.TagUseCount,
        ta.PostLinkCount,
        ta.ExcerptTitle,
        ta.WikiTitle,
        RANK() OVER (ORDER BY ta.TagUseCount DESC) AS TagRank
    FROM TagAgg ta
    WHERE ta.TagUseCount > 1000
)

/*-----------------------------------------------------------
  Combine users and tags with a UNION ALL (set operator)
-----------------------------------------------------------*/
SELECT *
FROM (
    /* Users block */
    SELECT
        tu.Id                              AS EntityId,
        tu.DisplayWithLoc                  AS EntityName,
        tu.Reputation                      AS Score,
        tu.CompositeRank                   AS Rank,
        'User'                             AS EntityType,
        tu.LocationGroup                   AS GroupInfo,
        NULL::varchar                      AS TagName,
        NULL::int                          AS TagRank
    FROM TopUsers tu

    UNION ALL

    /* Tags block */
    SELECT
        NULL::int                          AS EntityId,
        tt.TagName                         AS EntityName,
        tt.TagUseCount                     AS Score,
        tt.TagRank                         AS Rank,
        'Tag'                              AS EntityType,
        NULL::varchar                      AS GroupInfo,
        tt.TagName                         AS TagName,
        tt.TagRank                         AS TagRank
    FROM TopTags tt
) AS Combined
ORDER BY EntityType, Rank
LIMIT 100;
