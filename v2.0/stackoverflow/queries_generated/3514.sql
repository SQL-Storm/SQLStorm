-- {"query": "3514.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1718} 

/*  Benchmark query – combines CTEs, window functions, outer joins,
    correlated subqueries, set operators, string tricks and NULL logic   */
WITH
-- 1. Aggregate user activity, include users with no activity (LEFT JOIN)
UserStats AS (
    SELECT
        u.Id                      AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score),0)  AS TotalPostScore,
        COALESCE(COUNT(p.Id),0)   AS TotalPosts,
        COALESCE(SUM(v.UpVotes - v.DownVotes),0) AS NetVotes,
        COALESCE(MAX(p.CreationDate), u.CreationDate) AS FirstContributionDate
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ) v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),

-- 2. Explode tags for each question and compute tag‑level popularity
TagStats AS (
    SELECT
        t.TagName,
        COUNT(*)                              AS QuestionCount,
        SUM(p.Score)                          AS TotalScore,
        AVG(p.ViewCount)                      AS AvgViews,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM Posts p
    JOIN LATERAL (
        SELECT regexp_split_to_table(
                   TRIM(BOTH '<>' FROM p.Tags),
                   '><'
               ) AS TagName
    ) t ON true
    WHERE p.PostTypeId = 1                -- only questions
    GROUP BY t.TagName
),

-- 3. Latest comment per post (correlated subquery)
LatestComment AS (
    SELECT
        c.PostId,
        c.Text AS CommentText,
        c.CreationDate
    FROM Comments c
    WHERE c.Id = (
        SELECT MAX(c2.Id)
        FROM Comments c2
        WHERE c2.PostId = c.PostId
    )
),

-- 4. Top N questions per tag using window function
TopQuestionsPerTag AS (
    SELECT
        p.Id               AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    JOIN LATERAL (
        SELECT regexp_split_to_table(
                   TRIM(BOTH '<>' FROM p.Tags),
                   '><'
               ) AS TagName
    ) t ON true
    WHERE p.PostTypeId = 1                -- questions only
),

-- 5. Combine top questions and top answers (set operator)
CombinedTopPosts AS (
    SELECT
        q.PostId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.TagName,
        'Question' AS PostKind
    FROM TopQuestionsPerTag q
    WHERE q.rn <= 5

    UNION ALL

    SELECT
        a.Id               AS PostId,
        a.Title,
        a.Score,
        a.ViewCount,
        COALESCE(t.TagName,'<no‑tag>') AS TagName,
        'Answer' AS PostKind
    FROM Posts a
    LEFT JOIN Posts q ON q.Id = a.ParentId          -- question of this answer
    LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(
                   TRIM(BOTH '<>' FROM q.Tags),
                   '><'
               ) AS TagName
    ) t ON true
    WHERE a.PostTypeId = 2                         -- answers only
      AND a.Score >= 10
),

-- 6. Badge summary per user (outer join to keep users without badges)
UserBadges AS (
    SELECT
        u.Id                               AS UserId,
        COUNT(b.Id)                        AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, '; ')  AS BadgeList
    FROM Users u
    LEFT JOIN Badges b
        ON b.UserId = u.Id
    GROUP BY u.Id
)

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPostScore,
    us.TotalPosts,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    COALESCE(ub.BadgeList,'<none>')               AS Badges,
    ts.TagName,
    ts.QuestionCount,
    ts.TotalScore,
    ts.AvgViews,
    ts.TagRank,
    cp.PostId,
    cp.Title,
    cp.Score,
    cp.ViewCount,
    cp.PostKind,
    lc.CommentText,
    lc.CreationDate AS LatestCommentDate
FROM UserStats us
LEFT JOIN UserBadges ub          ON ub.UserId = us.UserId
LEFT JOIN (
    SELECT *
    FROM TagStats
    WHERE TagRank <= 10          -- focus on top 10 tags
) ts                           ON TRUE               -- cartesian to attach tag info
LEFT JOIN CombinedTopPosts cp   ON cp.TagName = ts.TagName
LEFT JOIN LatestComment lc      ON lc.PostId = cp.PostId
WHERE
    /* Complex predicate mixing NULL logic and calculations */
    (us.Reputation > 5000 AND ub.GoldBadges > 0)
    OR (us.TotalPosts >= 20 AND cp.Score IS NOT NULL AND cp.Score > 5)
    OR (us.TotalPostScore IS NULL OR us.TotalPostScore = 0)
ORDER BY
    us.Reputation DESC,
    ts.TagRank,
    cp.Score DESC NULLS LAST,
    cp.PostId;
