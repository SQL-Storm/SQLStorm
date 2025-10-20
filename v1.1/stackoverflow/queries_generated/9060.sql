-- {"query": "9060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3785} 

WITH
-- 1. Get the 100 most recent questions and answers posted in the last 30 days, partitioned by type
RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    WHERE p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days'
),

TopPosts AS (
    SELECT
        Id,
        OwnerUserId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        Tags
    FROM RecentPosts
    WHERE rn <= 100
),

-- 2. Aggregate per‑user statistics: number of questions, answers, net votes, bounty sums
UserScores AS (
    SELECT
        u.Id              AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)    AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)    AS AnswersProvided,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN v.BountyAmount ELSE 0 END),0) AS TotalBounty,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END)                                        AS NetVotes
    FROM Users AS u
    LEFT JOIN Posts  AS p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  AS v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),

-- 3. Compute per‑tag usage and average score for questions
TagUsage AS (
    SELECT
        UNNEST(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS Tag,
        COUNT(*)                                                AS UsageCount,
        AVG(p.Score)::numeric(10,2)                             AS AvgScore
    FROM Posts AS p
    WHERE p.PostTypeId = 1
    GROUP BY 1
),

-- 4. Pick each user's three most recent badges, then aggregate their names
BadgeRanks AS (
    SELECT
        b.UserId,
        b.Name,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC, b.Class ASC) AS rn
    FROM Badges AS b
),
TopBadges AS (
    SELECT
        br.UserId,
        STRING_AGG(br.Name, ', ' ORDER BY br.rn) AS RecentBadges
    FROM BadgeRanks AS br
    WHERE br.rn <= 3
    GROUP BY br.UserId
),

-- 5. Assemble the main result set with lateral subqueries, outer joins, window functions, and NULL logic
FinalSet AS (
    SELECT
        tp.Id                                   AS PostId,
        u.DisplayName,
        us.QuestionsAsked,
        us.AnswersProvided,
        us.NetVotes,
        us.TotalBounty,
        tp.PostTypeId,
        COALESCE(lc.Text, '(no comments)')       AS LastComment,
        CASE WHEN dup.RelatedPostId IS NOT NULL THEN 'Duplicate' ELSE 'Original' END AS LinkStatus,
        COALESCE(tb.RecentBadges, '(none)')      AS RecentBadges,
        COALESCE(tu.TagsConcatenated, '(none)')  AS TagsList,
        COALESCE(tu.ScoreSum, 0)                 AS TagScoreSum,
        -- Use a window function to rank posts by view count within each PostType
        RANK() OVER (PARTITION BY tp.PostTypeId ORDER BY tp.ViewCount DESC) AS ViewRank
    FROM TopPosts AS tp
    LEFT JOIN Users     AS u  ON u.Id = tp.OwnerUserId
    LEFT JOIN UserScores AS us ON us.UserId = u.Id
    LEFT JOIN LATERAL (
        SELECT c.Text
        FROM Comments AS c
        WHERE c.PostId = tp.Id
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS lc ON TRUE
    LEFT JOIN (
        SELECT DISTINCT RelatedPostId
        FROM PostLinks
        WHERE LinkTypeId = 3
    ) AS dup ON dup.RelatedPostId = tp.Id
    LEFT JOIN TopBadges AS tb ON tb.UserId = u.Id
    LEFT JOIN LATERAL (
        SELECT
            STRING_AGG(sub_tag, '|') AS TagsConcatenated,
            SUM(sub_score)        AS ScoreSum
        FROM (
            SELECT
                UNNEST(string_to_array(substring(tp.Tags,2,length(tp.Tags)-2),'><')) AS sub_tag,
                COALESCE(p2.Score,0)                                         AS sub_score
            FROM Posts AS p2
        ) AS tag_exp
    ) AS tu ON TRUE
),

-- 6. Create an “extra” set from tags to demonstrate a SET OPERATOR union
ExtraSet AS (
    SELECT
        NULL::int   AS PostId,
        NULL::text  AS DisplayName,
        tu.UsageCount     AS QuestionsAsked,
        NULL::int        AS AnswersProvided,
        CAST(tu.AvgScore AS int) AS NetVotes,
        NULL::int        AS TotalBounty,
        NULL::smallint  AS PostTypeId,
        NULL::text      AS LastComment,
        NULL::text      AS LinkStatus,
        NULL::text      AS RecentBadges,
        tu.Tag           AS TagsList,
        NULL::numeric   AS TagScoreSum,
        NULL::int       AS ViewRank
    FROM TagUsage AS tu
    WHERE tu.UsageCount > 50
)

-- 7. Final punch: combine, then subtract a slice with EXCEPT
SELECT * FROM FinalSet
UNION
SELECT * FROM ExtraSet
EXCEPT
SELECT * FROM FinalSet WHERE TotalBounty = 0;
